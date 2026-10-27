# frozen_string_literal: true

module Admin
  # Private preparation, source recovery and review using ordinary saved forms.
  class DepartureBatchesController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin
    before_action(except: %i[index create]) do
      @batch = DepartureBatch.select(*(DepartureBatch.column_names - ['plan']), Arel.sql("plan - 'sources' AS plan"))
                             .find(params.expect(:id))
    end
    rescue_from ArgumentError, KeyError, ActiveRecord::RecordInvalid, Season::OperationInProgress, with: :review_error

    def index
      season = params[:season_id].present? ? Season.find(params.expect(:season_id)) : Season.order(year: :desc).first
      page[:season] = season
      page[:batches] = Departures::BatchPage.listing(season)
      page[:preparation] = Departures::PreparationForm.defaults(season.year) if season
    end

    def show
      @page = page.merge(Departures::BatchPage.new(batch, params).call)
    end

    def create
      page[:season] = Season.find(params.expect(:season_id))
      return create_capture if params[:capture]

      page[:preparation] = params.require(:preparation).to_unsafe_h
      batch = Departures::BatchPreparation.create(page[:season], page[:preparation])
      redirect_to admin_departure_batch_path(batch), notice: I18n.t('admin.departure_batches.prepared')
    end

    def update
      return update_preparation if params[:preparation]

      fields = params.require(:review).to_unsafe_h
      Departures::DecisionEditor.new(batch, fields.fetch('review_key')).save(fields)
      redirect_to admin_departure_batch_path(batch), notice: I18n.t('admin.departure_batches.saved')
    end

    def acquire
      preparation = if params[:capture_only] == '1' || Departures::CapturePreparation.capture_only?(batch.plan)
                      Departures::CapturePreparation
                    else
                      Departures::BatchPreparation
                    end
      attempt = preparation.new(batch).acquire(params.permit(:close_interrupted).to_h)
      AcquireDepartureBatchJob.perform_later(attempt.id)
      redirect_to admin_departure_batch_path(batch), notice: I18n.t('admin.departure_batches.queued')
    end

    def coverage
      page[:coverage_fields] = params.require(:coverage).to_unsafe_h
      Departures::PreparedCoverageReview.new(batch).save(page[:coverage_fields], reviewer: current_user.email)
      redirect_to admin_departure_batch_path(batch), notice: I18n.t('admin.departure_batches.coverage_saved')
    end

    def recover
      Departures::BatchSuccessor.new(batch).recover(params.require(:recovery).to_unsafe_h)
      redirect_to admin_departure_batch_path(batch), notice: I18n.t('admin.departure_batches.recovered')
    end

    def correct
      correction = Departures::BatchSuccessor.new(batch).correct(params.expect(:reason))
      redirect_to admin_departure_batch_path(correction),
                  notice: I18n.t('admin.departure_batches.correction')
    end

    def source
      attempt_id = batch.acquisitions.select(:id).find(params.expect(:attempt_id)).id
      metadata = Departures::SourceHistory.new(batch, attempt_id:).source(params.expect(:source_id))
      bytes = Departures::RetainedSourceReader.new(attempt_id).bytes(metadata)
      extension = self.class.source_extension(metadata)
      send_data bytes, type: 'text/plain', disposition: 'attachment', filename: "departure-source-#{attempt_id}.#{extension}"
    end

    def self.source_extension(metadata)
      metadata.fetch('snapshot_kind') == 'raw_json' ? 'json' : 'html'
    end

    private

    attr_reader :batch

    def require_admin
      head :not_found unless current_user.admin?
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

    def create_capture
      page[:capture] = params.require(:capture).to_unsafe_h
      batch = Departures::CapturePreparation.create(page[:season], page[:capture])
      AcquireDepartureBatchJob.perform_later(batch.attempt.id)
      redirect_to admin_departure_batch_path(batch), notice: I18n.t('admin.departure_batches.queued')
    end

    def update_preparation
      page[:preparation] = params.require(:preparation).to_unsafe_h

      Departures::BatchPreparation.new(batch).save(page[:preparation])
      redirect_to admin_departure_batch_path(batch), notice: I18n.t('admin.departure_batches.saved')
    end
  end
end
