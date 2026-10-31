# frozen_string_literal: true

module Ingestion
  # An explicit correction may change an unlinked opponent, never a rated participant.
  class NameOnlyScheduleCandidate
    def initialize(evidence)
      @evidence = evidence
    end

    def validate
      validate_pending_game
      validate_identity
      validate_memberships
      validate_payloads
      validate_outputs
    end

    def self.output_ids(game)
      [Prediction, GameOdd, BookmakerOdd, BetRecommendation].to_h do |model|
        [model.table_name, model.where(game_id: game.id).ids]
      end
    end

    private

    attr_reader :evidence

    def game = evidence.game
    def incoming = evidence.incoming.data

    def previous
      @previous ||= GameObservation.new(evidence.prior.normalized_payload).validate
    end

    def validate_outputs
      return unless self.class.output_ids(game).values.any?(&:any?)

      raise ArgumentError, 'Saved forecasts, odds or betting outputs prevent participant correction.'
    end

    def validate_pending_game
      raise ArgumentError, 'Only unplayed, scoreless schedule entries can be reviewed.' unless ScheduleReviewCandidate.pending_game?(game)

      date = game.schedule_date
      season = evidence.season
      return if game.season_id == season.id && date >= Game.current_schedule_date && (season.start_date..season.end_date).cover?(date)

      raise ArgumentError, 'Only upcoming games inside the target season can be reviewed.'
    end

    def validate_identity
      return if matching_identity?

      raise ArgumentError, 'Participant correction requires accepted evidence for the same active CBBD game key/profile.'
    end

    def matching_identity?
      prior = evidence.prior
      active = GameExternalIdentity.active.find_by(game:, provider: 'cbbd')
      key = incoming[:external_game_id]
      prior && prior.attributes.values_at('provider', 'semantic_profile', 'external_game_id') ==
        ['cbbd', incoming[:semantic_profile], key] && active&.external_id == key
    end

    def validate_memberships
      unless unchanged_memberships?
        raise ArgumentError, 'Only one name-only opponent can change; linked participant memberships must remain unchanged.'
      end

      GameObservation::SIDES.each_with_index { |label, index| validate_side_identity(label, index) }
    end

    def unchanged_memberships?
      resolution = evidence.resolution
      old_resolution = ObservationResolution.new(previous, evidence.season).resolve
      expected = GameScheduleReview.participants_for(resolution)
      resolution.memberships.one?(&:nil?) && expected == GameScheduleReview.participants_for(old_resolution) &&
        expected == GameScheduleReview.stored_participants(game)
    end

    def validate_side_identity(label, index)
      old_side = previous.data.fetch(label)
      unless game.public_send("#{label}_team_name") == old_side[:name]
        raise ArgumentError, 'Stored participant names changed; review the current accepted evidence.'
      end
      return unless evidence.resolution.memberships[index]
      return if old_side.slice(:name, :external_team_id) == incoming.fetch(label).slice(:name, :external_team_id)

      raise ArgumentError, 'Linked participant identity and orientation must remain unchanged.'
    end

    def validate_payloads
      pending = [previous.data, incoming].all? { |data| ScheduleReviewCandidate.pending_payload?(data, evidence.season) }
      raise ArgumentError, 'Only upcoming, unplayed schedule entries can be reviewed.' unless pending
    end
  end
end
