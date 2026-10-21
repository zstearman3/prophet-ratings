# frozen_string_literal: true

module Admin
  # Private preparation, source recovery and review using ordinary saved forms.
  class DepartureBatchesController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin
    before_action :load_batch, except: %i[index create]
    rescue_from ArgumentError, KeyError, ActiveRecord::RecordInvalid, Season::OperationInProgress, with: :review_error

    def index
      season = params[:season_id].present? ? Season.find(params.expect(:season_id)) : Season.order(year: :desc).first
      page[:season] = season
      page[:batches] = DepartureBatch.where(season:).order(id: :desc)
      page[:preparation] = Departures::PreparationForm.defaults(season.year) if season
    end

    def show
      page[:preparation] ||= Departures::BatchPreparation.new(batch).form_attributes
      page[:review] = Departures::BatchReview.new(batch)
      page[:report] = page[:review].report
      page[:identity] = Departures::TeamIdentity.new
      page[:row_issues] = Departures::DecisionForm.new(batch.attempt&.dataset || {}).issues(batch.decisions)
    end

    def create
      page[:season] = Season.find(params.expect(:season_id))
      page[:preparation] = params.require(:preparation).to_unsafe_h
      return render :index if add_source?

      batch = Departures::BatchPreparation.create(page[:season], page[:preparation])
      redirect_to admin_departure_batch_path(batch), notice: I18n.t('admin.departure_batches.prepared')
    end

    def update
      return update_preparation if params[:preparation]

      Departures::BatchReview.new(batch).save(params.require(:review).to_unsafe_h)
      redirect_to admin_departure_batch_path(batch), notice: I18n.t('admin.departure_batches.saved')
    end

    def acquire
      attempt = Departures::BatchPreparation.new(batch).acquire
      AcquireDepartureBatchJob.perform_later(attempt.id)
      redirect_to admin_departure_batch_path(batch), notice: I18n.t('admin.departure_batches.queued')
    end

    def recover
      Departures::BatchAcquisition.new(batch.attempt).recover(params.require(:recovery).to_unsafe_h)
      redirect_to admin_departure_batch_path(batch), notice: I18n.t('admin.departure_batches.recovered')
    end

    def publish
      Departures::BatchReview.new(batch).publish(params.require(:review).to_unsafe_h, reviewer: current_user.email)
      redirect_to admin_departure_batch_path(batch), notice: I18n.t('admin.departure_batches.published')
    end

    def correct
      correction = Departures::BatchPreparation.new(batch).correct(params.expect(:reason))
      redirect_to admin_departure_batch_path(correction),
                  notice: I18n.t('admin.departure_batches.correction')
    end

    def source
      attempt = batch.acquisitions.find(params.expect(:attempt_id))
      bytes = Departures::RetainedEvidence.new(attempt).bytes(params.expect(:source_id))
      send_data bytes, type: 'text/plain', disposition: 'attachment', filename: "departure-source-#{attempt.id}.html"
    end

    private

    attr_reader :batch

    def require_admin
      head :not_found unless current_user.admin?
    end

    def load_batch
      @batch = DepartureBatch.find(params.expect(:id))
    end

    def add_source?
      return false unless params[:add_source] == '1'

      Departures::PreparationForm.add_source(page[:preparation])
      true
    end

    def review_error(error)
      page[:error] = error.message
      return render plain: page[:error], status: :unprocessable_content unless batch || page[:season]

      show if batch
      render batch ? :show : :index, status: :unprocessable_content
    end

    def page
      @page ||= { batches: [], error: nil }
    end

    def update_preparation
      page[:preparation] = params.require(:preparation).to_unsafe_h
      return render(:show) if add_source? && show

      Departures::BatchPreparation.new(batch).save(page[:preparation])
      redirect_to admin_departure_batch_path(batch), notice: I18n.t('admin.departure_batches.saved')
    end
  end
end
