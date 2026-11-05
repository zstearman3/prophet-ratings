# frozen_string_literal: true

module Admin
  # Format private operational comparisons and their explicit resolution controls.
  module GameIngestionIssuesHelper
    ISSUE_LABELS = { 'scoring' => 'Scoring discrepancy', 'participants' => 'Participant conflict', 'missing_result' => 'Missing result',
                     'source_revision' => 'Source correction', 'invalid' => 'Invalid source data' }.freeze
    ISSUE_STEPS = {
      'scoring' => 'The reported final score already counts toward ratings. Acknowledge it or select a different supplied total.',
      'participants' => 'Compare the participants, select the correct teams, then apply the saved result and box stats.',
      'missing_result' => 'The source has not supplied a usable final result. Retry this game after the source is corrected.',
      'source_revision' => 'The source changed a completed result without ordering evidence. Compare the stored result before accepting.',
      'invalid' => 'Source evidence failed validation. Inspect the retained values, then retry after correction.'
    }.freeze

    def self.ingestion_issue_title(issue)
      ISSUE_LABELS.fetch(issue.category)
    end

    def self.ingestion_issue_steps(issue)
      ISSUE_STEPS.fetch(issue.category)
    end

    def self.ingestion_issue_matchup(issue)
      payload = issue.source_payload
      "#{payload.dig('away', 'name')} @ #{payload.dig('home', 'name')}"
    end

    def self.ingestion_score_candidates(issue)
      Ingestion::ScoringReviewEvidence.new(issue.latest_observation, issue.season).validate.candidates
    rescue ArgumentError
      {}
    end

    def self.ingestion_team_options(issue, label)
      source = issue.source_payload.fetch(label)
      [["Source opponent: #{source['name']} (untracked)", 'source']] +
        issue.season.team_seasons.includes(:team).map { |membership| [membership.team.school, membership.team_id.to_s] }.sort
    end

    def self.ingestion_selected_team(issue, label)
      game = issue.game
      sides = { 'home' => game&.home_team_game, 'away' => game&.away_team_game }
      sides[label]&.team_id.to_s.presence || 'source'
    end
  end
end
