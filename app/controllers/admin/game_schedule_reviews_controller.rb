# frozen_string_literal: true

module Admin
  # Compare retained pending schedules; an explicit choice is the approval, with no reason input.
  class GameScheduleReviewsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin
    before_action :load_page
    rescue_from ArgumentError, ActiveRecord::RecordInvalid, with: :invalid_submission
    rescue_from Ingestion::GamesIngestionService::ImportInProgress, with: :import_busy
    helper Admin::ScheduleRefreshRunsHelper
    helper_method :page

    def show; end

    def update
      run, source = page.values_at(:run, :observation)
      Ingestion::ScheduleReviewResolution.new(run:, observation: source, user: current_user,
                                              choice: params[:choice], fingerprint: params[:fingerprint]).call
      redirect_to admin_schedule_refresh_run_game_schedule_review_path(run, source)
    end

    private

    attr_reader :page

    def require_admin
      head :not_found unless current_user.admin?
    end

    def load_page
      run = ScheduleRefreshRun.find(params.expect(:schedule_refresh_run_id))
      source = run.rejection_observations[params.expect(:id).to_i]
      raise ActiveRecord::RecordNotFound unless source && run.cbbd? && !run.historical?

      @page = { run:, observation: source, review: GameScheduleReview.find_by(source_observation: source) }
      load_comparison unless page[:review]
    end

    def load_comparison
      run, source = page.values_at(:run, :observation)
      raise ArgumentError, 'Wait for the schedule run to finish before reviewing.' unless ScheduleRefreshRun::TERMINAL.include?(run.status)

      page[:evidence] = Ingestion::ScheduleReviewEvidence.new(source, run.season).validate
    rescue ArgumentError => error
      page[:error] = error.message
    end

    def invalid_submission(error)
      page[:error] = error.message
      render :show, status: :unprocessable_content
    end

    def import_busy(error)
      page[:error] = "#{error.message} Wait for it to finish, reload the comparison, and try again."
      render :show, status: :conflict
    end
  end
end
