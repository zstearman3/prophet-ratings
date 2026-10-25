# frozen_string_literal: true

module Ingestion
  # Append one attempt without rewriting accepted provenance or discarding rejected evidence.
  class ObservationAudit
    PROJECTION_REASON = 'missing_stable_game_identity_projection'

    def initialize(observation, game)
      @data = observation.data
      @game = game
    end

    def retain(outcome, reason, options = {})
      record = ::GameObservation.create!(audit_attributes(outcome, reason, options))
      self.class.report(record).merge(changes: options.fetch(:changes, {}), unmatched: options.fetch(:unmatched, []),
                                      possible_move_ids: possible_moves)
    end

    def self.report(record)
      game_id, outcome, reason, accepted = record.attributes.values_at('game_id', 'outcome', 'reason', 'accepted')
      projected = %w[projected unchanged].include?(outcome) && reason == PROJECTION_REASON
      { outcome:, reason:, game_id:, observation_id: record.id, accepted:, projected:,
        scheduled: record.normalized_payload['source_status'] == 'scheduled',
        applied: accepted || projected || (outcome == 'unchanged' && game_id.present?) }
    end

    private

    attr_reader :data, :game

    def audit_attributes(outcome, reason, options)
      review, accepted = options.values_at(:scoring_review, :accepted)
      reason = "admin_reviewed_scoring: #{reason}" if review
      attributes.merge(outcome:, reason:, accepted: accepted || false, scoring_review: review)
    end

    def attributes
      { game_id: persisted_game_id, provider: data[:provider], external_game_id: data[:external_game_id],
        semantic_profile: data[:semantic_profile], normalized_payload: data.except(:raw_payload).as_json,
        raw_payload: data.fetch(:raw_payload, {}).as_json, payload_digest: data[:payload_digest],
        captured_at: data[:captured_at], source_updated_at: data[:source_updated_at] }
    end

    def persisted_game_id
      id = game&.id
      id if id && Game.exists?(id)
    end

    def possible_moves
      return [] unless game&.persisted?

      game.season.games.scheduled.where(home_team_name: data[:home][:name],
                                        away_team_name: data[:away][:name]).where.not(id: game.id).pluck(:id)
    end
  end
end
