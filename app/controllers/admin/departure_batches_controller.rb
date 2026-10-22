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
      page[:batches] = Departures::BatchPage.listing(season)
      page[:preparation] = Departures::PreparationForm.defaults(season.year) if season
    end

    def show
      page[:preparation] ||= Departures::BatchPreparation.new(batch).form_attributes
      @page = page.merge(Departures::BatchPage.new(batch).call)
    end

    def create
      page[:season] = Season.find(params.expect(:season_id))
      page[:preparation] = params.require(:preparation).to_unsafe_h

      batch = Departures::BatchPreparation.create(page[:season], page[:preparation])
      redirect_to admin_departure_batch_path(batch), notice: I18n.t('admin.departure_batches.prepared')
    end

    def update
      return update_preparation if params[:preparation]

      Departures::BatchReview.new(batch).save(params.require(:review).to_unsafe_h)
      redirect_to admin_departure_batch_path(batch), notice: I18n.t('admin.departure_batches.saved')
    end

    def acquire
      attempt = Departures::BatchPreparation.new(batch).acquire(params.permit(:close_interrupted).to_h)
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
      id = params.expect(:source_id)
      bytes = Departures::RetainedEvidence.new(attempt).bytes(id)
      send_data bytes, type: 'text/plain', disposition: 'attachment', filename: Departures::RetainedEvidence.new(attempt).filename(id)
    end

    private

    attr_reader :batch

    def require_admin
      head :not_found unless current_user.admin?
    end

    def load_batch
      @batch = DepartureBatch.find(params.expect(:id))
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

      Departures::BatchPreparation.new(batch).save(page[:preparation])
      redirect_to admin_departure_batch_path(batch), notice: I18n.t('admin.departure_batches.saved')
    end
  end
end
