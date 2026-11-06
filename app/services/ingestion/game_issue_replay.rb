# frozen_string_literal: true

module Ingestion
  # Only unchanged source facts and unchanged applied game state may reuse an admin selection.
  class GameIssueReplay
    def initialize(row:, season:)
      @row = row
      @season = season
      @payload = Cbbd::ImportObservation.new(row, season).payload
      @issue = nil
    end

    def call
      @issue = reviewed_issue
      return unless @issue
      return changed_source unless @issue.source_fingerprint == GameIngestionIssue.fingerprint(@payload)

      Game.transaction(requires_new: true) { replay }
    end

    private

    def reviewed_issue
      issues = GameIngestionIssue.where(season: @season, provider: @payload[:provider], external_game_id: @payload[:external_game_id])
      issues.order(id: :desc).detect { |entry| entry.latest_decision && entry.effective_payload.present? }
    end

    def changed_source
      source = ObservationAudit.new(GameObservation.new(@payload), @issue.game).retain('conflict', 'reviewed_source_changed')
      GameIssueRecorder.new(season: @season, report: source).call
      nil
    end

    def replay
      @issue.lock!
      candidate = @issue.game
      candidate&.lock!
      return retain_hold unless candidate && ScoringException.new(@issue).matches_game?(candidate)

      import_selection
    end

    def retain_hold
      ObservationAudit.new(GameObservation.new(@payload), @issue.game).retain('conflict', 'reviewed_game_changed')
    end

    def import_selection
      payload = @issue.effective_payload.merge('raw_payload' => @row, 'captured_at' => @payload[:captured_at])
      GameObservationImporter.new(observation: payload, season: @season, scoring_exception: ScoringException.new(@issue)).call
    end
  end
end
