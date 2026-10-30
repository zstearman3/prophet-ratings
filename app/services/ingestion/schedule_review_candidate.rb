# frozen_string_literal: true

module Ingestion
  # The review can change pending metadata, never participants, scores, boxes or provider semantics.
  class ScheduleReviewCandidate
    def initialize(evidence)
      @evidence = evidence
    end

    def validate
      raise ArgumentError, 'Only unplayed, scoreless schedule entries can be reviewed.' unless self.class.pending_game?(game)

      validate_memberships
      raise ArgumentError, 'The existing game has no accepted source evidence.' unless @evidence.prior

      validate_payloads
      validate_identities
    end

    def self.pending_payload?(data, season)
      date = Date.iso8601(data.fetch(:schedule_date))
      data.values_at(:source_status, :source_completed, :season_year) == ['scheduled', false, season.year] &&
        date >= Game.current_schedule_date && (season.start_date..season.end_date).cover?(date) &&
        data.values_at(:home, :away).all? { |side| side[:score].blank? && side[:stats].values.all?(&:nil?) }
    end

    def self.pending_game?(game)
      fields = GameObservation::STAT_KEYS.map(&:to_s)
      game.scheduled? && game.attributes.values_at('home_team_score', 'away_team_score').all?(&:nil?) &&
        TeamGame.where(game:).all? { |side| side.attributes.slice(*fields).values.all?(&:nil?) }
    end

    private

    def game = @evidence.game

    def validate_memberships
      resolution = @evidence.resolution
      expected = GameScheduleReview.participants_for(resolution)
      valid = resolution.memberships.all? && GameScheduleReview.stored_participants(game) == expected
      raise ArgumentError, 'Stored participant memberships must match the reviewed season memberships.' unless valid
    end

    def validate_payloads
      validate_profile
      [@evidence.prior.normalized_payload, @evidence.incoming.data].each do |payload|
        unless self.class.pending_payload?(GameObservation.new(payload).validate.data, @evidence.season)
          raise ArgumentError, 'Only upcoming, unplayed schedule entries can be reviewed.'
        end
      end
    end

    def validate_profile
      provider, profile, key = @evidence.prior.attributes.values_at('provider', 'semantic_profile', 'external_game_id')
      data = @evidence.incoming.data
      compatible = [provider, profile] == ['cbbd', data[:semantic_profile]] && key.present? && key != data[:external_game_id]
      raise ArgumentError, 'Review requires two distinct CBBD keys with the same statistical profile.' unless compatible
    end

    def validate_identities
      active = GameExternalIdentity.active.find_by(game:, provider: 'cbbd')
      incoming_id = @evidence.incoming.data[:external_game_id]
      available = active&.external_id == @evidence.prior.external_game_id && incoming_id.present? &&
                  !GameExternalIdentity.exists?(provider: 'cbbd', external_id: incoming_id)
      raise ArgumentError, 'Source identity changed or already belongs to a game; refresh identity review.' unless available
    end
  end
end
