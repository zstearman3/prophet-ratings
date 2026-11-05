# frozen_string_literal: true

module Admin
  # Private source comparisons and explicit resolution; GET never changes ingestion state.
  class GameIngestionIssuesController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin
    before_action :load_issue, only: %i[show update retry]
    rescue_from ArgumentError, ActiveRecord::RecordInvalid, Season::OperationInProgress,
                Ingestion::GamesIngestionService::ImportInProgress, with: :invalid_submission

    def index
      @page = Ingestion::GameIssueListing.new(params.permit(:season_id, :category, :state, :date, :page)).call
    end

    def show; end

    def update
      submission = params.expect(resolution: [:action, :fingerprint, { values: %i[home away] }]).to_h.symbolize_keys
      Ingestion::GameIssueResolution.new(issue:, user: current_user, **submission.merge(values: submission[:values] || {})).call
      redirect_to admin_game_ingestion_issue_path(issue)
    end

    def retry
      Ingestion::GameIssueRetry.new(issue:, user: current_user, fingerprint: params[:fingerprint]).enqueue
      redirect_to admin_game_ingestion_issue_path(issue), notice: t('admin.game_ingestion_issues.retry_queued')
    end

    private

    attr_reader :issue

    def require_admin
      head :not_found unless current_user.admin?
    end

    def load_issue
      @issue = GameIngestionIssue.includes(:game, :season, :latest_observation, decisions: :actor).find(params.expect(:id))
    end

    def invalid_submission(error)
      if issue
        @error = error.message
        render :show, status: :unprocessable_content
      else
        redirect_to admin_game_ingestion_issues_path, alert: t('admin.game_ingestion_issues.invalid_filter')
      end
    end
  end
end
