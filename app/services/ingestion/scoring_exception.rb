# frozen_string_literal: true

module Ingestion
  # An exact persisted source exception to points arithmetic, never a general validation bypass.
  class ScoringException
    def initialize(issue)
      @issue = issue
      @payload = issue.effective_payload
      @context = {}
    end

    def self.for_game(game)
      GameIngestionIssue.where(game:).where.not(effective_payload: {}).order(id: :desc).filter_map do |issue|
        exception = new(issue)
        exception if exception.matches_game?(game)
      end.first
    end

    def matches_payload?(payload)
      @issue.persisted? && @payload.present? && GameIngestionIssue.fingerprint(@payload) == GameIngestionIssue.fingerprint(payload)
    end

    def validate_payload(payload, resolution)
      return if matches_payload?(payload) && @issue.participants == GameScoringReview.participants_for(resolution)

      raise GameObservation::Invalid, 'Scoring exception no longer matches source or participants'
    end

    def matches_game?(game)
      @context[:game] = game
      @payload.present? && matching_context? && %w[home away].all? { |label| matching_side?(label) }
    end

    private

    def matching_context?
      game = @context.fetch(:game)
      timestamp = @payload['start_time']
      game.season_id == @issue.season_id && game.schedule_date.iso8601 == @payload['schedule_date'] &&
        (!timestamp || game.start_time == Time.iso8601(timestamp))
    end

    def matching_side?(label)
      game = @context.fetch(:game)
      expected = @payload.fetch(label)
      names_match = game.public_send("#{label}_team_name") == expected['name']
      scores_match = game.public_send("#{label}_team_score") == expected['score']
      names_match && scores_match && matching_counts?(label)
    end

    def matching_counts?(label)
      game = @context.fetch(:game)
      side = game.public_send("#{label}_team_game")
      identity = @issue.participants.fetch(label)
      return side.blank? if game.persisted? && identity['team_season_id'].blank?

      side && matching_identity?(side, identity) && matching_stats?(side, label)
    end

    def matching_stats?(side, label)
      @payload.fetch(label).fetch('stats').all? { |key, value| side.public_send(key) == value }
    end

    def matching_identity?(side, identity)
      !@context.fetch(:game).persisted? || side.attributes.slice('team_id', 'team_season_id') == identity
    end
  end
end
