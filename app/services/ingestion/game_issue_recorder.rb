# frozen_string_literal: true

module Ingestion
  # Persist row-level failures and reopen decisions when their substantive source facts change.
  class GameIssueRecorder
    def initialize(season:, report:)
      @season = season
      @report = report
      @observation = ::GameObservation.find(report.fetch(:observation_id))
    end

    def call
      refresh_existing
      return retain_issue if GameSyncProvider.held?(@report)

      resolve_issues
      []
    end

    def report
      @report.merge(issue_ids: (@report.fetch(:issue_ids, []) + call).uniq)
    end

    private

    def resolve_issues
      scoring_warning = ScoringReviewEvidence.reviewable?(@observation.raw_payload, @season)
      matching.find_each do |issue|
        issue.update!(state: 'resolved') unless issue.category == 'scoring' && scoring_warning
      end
    end

    def matching
      GameIngestionIssue.where(season: @season, provider: @observation.provider, external_game_id: @observation.external_game_id)
    end

    def refresh_existing
      matching.find_each { |issue| issue.with_lock { issue.observe(@observation, candidate) } }
    end

    def retain_issue
      issue = GameIngestionIssue.capture!(season: @season, observation: @observation, category:, game: candidate)
      [issue.id]
    end

    def candidate
      game = @observation.game || GameExternalIdentity.find_by(provider: @observation.provider,
                                                               external_id: @observation.external_game_id)&.game
      game if game&.season_id == @season.id
    end

    def category
      case @observation.reason.to_s
      when /participant|identity|profile|season|candidate/ then 'participants'
      when /freshness|revision|reviewed_source_changed|reviewed_game_changed/ then 'source_revision'
      when /missing|incomplete|not confirmed final/ then 'missing_result'
      else @report[:final_box] == 'missing' ? 'missing_result' : 'invalid'
      end
    end
  end
end
