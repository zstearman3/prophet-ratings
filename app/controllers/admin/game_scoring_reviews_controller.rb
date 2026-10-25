# frozen_string_literal: true

module Admin
  # Resolve one retained rejection with a preview and explicit approval; GET never imports.
  class GameScoringReviewsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin
    before_action :load_evidence
    rescue_from ArgumentError, ActiveRecord::RecordInvalid, with: :invalid_submission
    rescue_from Ingestion::GamesIngestionService::ImportInProgress, with: :import_busy
    helper Admin::ScheduleRefreshRunsHelper
    helper_method :page

    def show; end

    def preview
      raise ArgumentError, 'This observation cannot be resolved by scoring review.' unless page[:reviewable]

      page[:choices] = submitted_choices
      page[:selected] = page.fetch(:evidence).selected_payload(page[:choices])
    end

    def update
      context = page.slice(:run, :observation)
      Ingestion::ScoringReviewImport.new(**context, user: current_user, choices: submitted_choices, confirmed: params[:confirmed]).call
      redirect_to admin_schedule_refresh_run_game_scoring_review_path(context[:run], context[:observation])
    end

    private

    attr_reader :page

    def require_admin
      head :not_found unless current_user.admin?
    end

    def submitted_choices
      params.expect(choices: %i[home away]).to_h
    end

    def load_evidence
      run = ScheduleRefreshRun.find(params.expect(:schedule_refresh_run_id))
      @page = { run:, observation: run.rejection_observations[params.expect(:id).to_i] }
      raise ActiveRecord::RecordNotFound unless page[:observation] && run.historical? && run.cbbd?

      load_review
    end

    def load_review
      season = page.fetch(:run).season
      source = page.fetch(:observation)
      evidence = Ingestion::ScoringReviewEvidence.new(source, season)
      page.merge!(evidence:, review: GameScoringReview.find_by(source_fingerprint: GameScoringReview.source_fingerprint(evidence.payload)),
                  reviewable: Ingestion::ScoringReviewEvidence.reviewable?(source, season) &&
                              ScheduleRefreshRun::TERMINAL.include?(page[:run].status))
    rescue ArgumentError
      page[:reviewable] = false
    end

    def import_busy(error)
      page[:error] = "#{error.message} Wait for it to finish, then try again with the same selection."
      render :show, status: :conflict
    end

    def invalid_submission(error)
      page[:error] = error.message
      render :show, status: :unprocessable_content
    end
  end
end
