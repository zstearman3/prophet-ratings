# frozen_string_literal: true

module Ingestion
  # All provider imports share identity, transaction, freshness and strict finalization rules.
  class GameObservationImporter
    def initialize(observation:, season: nil)
      @observation = observation.is_a?(GameObservation) ? observation : GameObservation.new(observation)
      @season = season
    end

    def call
      prepare_resolution
      apply_transaction
    rescue ObservationResolution::Held, GameObservation::Invalid, GameExternalIdentity::Conflict,
           ProphetRatings::GameFinalizer::MissingDerivedStatsError => error
      retain_error(error)
    end

    def self.error_details(error)
      case error
      when ObservationResolution::Held then { outcome: error.outcome, unmatched: error.participants }
      when GameExternalIdentity::Conflict then { outcome: 'conflict' }
      else { outcome: 'invalid' }
      end
    end

    private

    attr_reader :observation, :resolution, :game

    def data = observation.data

    def apply_transaction
      Game.transaction(requires_new: true) do
        resolution.lock
        @game = resolution.game
        lock_game
        apply_observation
      end
    end

    def prepare_resolution
      observation.validate
      @season ||= Season.find_by(year: data[:season_year])
      @resolution = ObservationResolution.new(observation, @season).resolve
    end

    def lock_game
      if game
        game.lock!
        resolution.validate_game(game)
      else
        @game = Game.new
      end
    end

    def apply_observation
      return ObservationScheduleProjection.new(observation, resolution, game).call if observation.schedule_projection?

      writer = ObservationWriter.new(observation, resolution, game)
      if writer.identical?
        associate_identity
        return retain('unchanged', 'canonical_values_unchanged')
      end
      write_observation(writer)
    end

    def validate_update
      ObservationFreshness.new(observation, game).validate
      observation.validate_duration if observation.strict_final?
    end

    def write_observation(writer)
      validate_update
      changes = writer.changes
      writer.call
      associate_identity
      retain(outcome, outcome_reason, accepted: true, changes:)
    end

    def outcome_reason
      outcome == 'incomplete' ? 'missing_required_box_data' : "source_#{data[:source_status]}"
    end

    def associate_identity
      identity = GameExternalIdentity.associate!(game:, provider: data[:provider], external_id: data[:external_game_id])
      raise ObservationResolution::Held.new('superseded', 'superseded_game_identity') if identity.superseded?
    end

    def outcome
      status = data[:source_status]
      status == 'final' && !observation.strict_final? ? 'incomplete' : status
    end

    def retain_error(error)
      details = self.class.error_details(error)
      retain(details.fetch(:outcome), error.message, details)
    end

    def retain(outcome, reason, options = {})
      ObservationAudit.new(observation, game).retain(outcome, reason, options)
    end
  end
end
