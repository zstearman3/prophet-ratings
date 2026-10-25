# frozen_string_literal: true

module Admin
  # Season-scoped bounded schedule acquisition; GET never imports or enqueues.
  class ScheduleRefreshRunsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin
    rescue_from ArgumentError, ActiveRecord::RecordInvalid, with: :invalid_submission

    def index
      load_listing
    end

    def show
      @run = ScheduleRefreshRun.find(params.expect(:id))
      observations = run.rejection_observations
      @evidence = { games: run.season.games.where(id: run.report_game_ids).index_by(&:id), observations:,
                    scoring_reviews: GameScoringReview.where(source_observation_id: observations.keys).index_by(&:source_observation_id) }
    end

    def create
      @values = params.expect(refresh: %i[provider start_date end_date max_requests retries mode rescan]).to_h
      @run = ScheduleRefreshRun.new(values.merge(season: Season.find(params.expect(:season_id)), requested_by: current_user))
      validate_policy
      run.save!
      enqueue
    end

    def retry
      @run = ScheduleRefreshRun.find(params.expect(:id))
      @run = run.create_retry!(current_user)
      enqueue
    end

    def defer
      season = Season.find(params.expect(:season_id))
      ScheduleDeferral.create!(season:, requested_by: current_user, reason: params[:reason].to_s.strip)
      redirect_to admin_schedule_refresh_runs_path(season_id: season.id), notice: I18n.t('admin.schedule_refresh_runs.deferred')
    end

    helper_method :run

    private

    attr_reader :run, :page, :values

    def validate_policy
      run.validate!
      Ingestion::GameSyncPolicy.new(run.provider, run.cbbd? ? { max_requests: run.max_requests, retries: run.retries } : {})
    end

    def enqueue
      queue_run
      redirect_to admin_schedule_refresh_run_path(run)
    end

    def queue_run
      queued = RefreshScheduleJob.perform_later(run.id)
      raise ActiveJob::EnqueueError unless queued
    rescue StandardError
      run.finish('failed', 'Job could not be queued. Check GoodJob and explicitly retry.')
    end

    def require_admin
      head :not_found unless current_user.admin?
    end

    def load_listing
      @page = ScheduleRefreshRun.listing(run&.season_id || params[:season_id])
      @values = values || default_window.merge('provider' => ENV.fetch('GAME_SYNC_PROVIDER', 'sports_reference'),
                                               'max_requests' => ENV.fetch('CBBD_MAX_REQUESTS', nil),
                                               'retries' => ENV.fetch('CBBD_RETRIES', nil))
    end

    def default_window
      season = page[:season]
      return {} unless season

      historical = season.end_date < Game.current_schedule_date
      first = historical ? season.start_date : [season.start_date, Game.current_schedule_date].max
      { 'mode' => historical ? 'historical' : 'upcoming', 'rescan' => false,
        'start_date' => first.iso8601, 'end_date' => [first + 6.days, season.end_date].min.iso8601 }
    end

    def invalid_submission(error)
      load_listing
      page[:error] = error.message
      render :index, status: :unprocessable_content
    end
  end
end
