# frozen_string_literal: true

module Admin
  # Human review of recruiting captures; every endpoint requires the existing admin login.
  class RecruitingBatchesController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin
    before_action :load_batch, only: %i[show update publish source]
    rescue_from ArgumentError, ActiveRecord::ActiveRecordError, Season::OperationInProgress, TeamExternalIdentity::Conflict,
                with: :review_error

    def index
      @listing = RecruitingBatch.listing(params[:season_id])
    end

    def show
      @report = review_report
    end

    def source
      send_data batch.source_bytes(params[:capture]), type: 'text/plain', disposition: 'attachment',
                                                      filename: "recruiting-batch-#{batch.id}-source.txt"
    end

    def create
      season = Season.find(params.expect(:season_id))
      batch = RecruitingBatch.create!(season:, source_year: season.year - 1,
                                      extract_bytes: JSON.generate('provider' => 'cbbd',
                                                                   'extraction_version' => Recruiting::CbbdExtract::VERSION))
      AcquireRecruitingBatchJob.perform_later(batch.id)
      redirect_to admin_recruiting_batch_path(batch), notice: I18n.t('admin.recruiting_batches.queued')
    end

    def update
      Recruiting::BatchReview.new(batch).save(params.require(:review).to_unsafe_h)
      redirect_to admin_recruiting_batch_path(batch, page: params[:page]), notice: I18n.t('admin.recruiting_batches.saved')
    end

    def publish
      Recruiting::BatchReview.new(batch).publish(params.require(:review).to_unsafe_h, reviewer: current_user.email)
      redirect_to admin_recruiting_batch_path(batch), notice: I18n.t('admin.recruiting_batches.published')
    end

    private

    attr_reader :batch

    def require_admin
      redirect_to root_path unless current_user.admin?
    end

    def load_batch
      @batch = RecruitingBatch.find(params.expect(:id))
    end

    def review_report
      Recruiting::BatchReview.new(batch).report if batch.status.in?(%w[ready published])
    rescue ArgumentError => error
      @review_error = error.message
      nil
    end

    def review_error(error)
      message = error.message
      @review_error = message
      return render plain: message, status: :unprocessable_content unless batch

      reload_review
      render :show, status: :unprocessable_content
    end

    def reload_review
      # Rolled-back approval attributes must not enter the retry form's review key.
      batch.reload
      show unless action_name == 'show'
    end
  end
end
