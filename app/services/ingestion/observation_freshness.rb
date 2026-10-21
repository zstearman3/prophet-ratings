# frozen_string_literal: true

module Ingestion
  # Capture time never establishes source ordering. Completed values need actual upstream evidence.
  class ObservationFreshness
    def initialize(observation, game)
      @observation = observation
      @game = game
    end

    def validate
      return validate_pending_revision unless @game.completed?

      hold('conflict', 'completed_game_cannot_downgrade') unless @observation.strict_final?
      return if @game.final_unmatched?

      validate_provenance
      validate_order
    end

    private

    def validate_pending_revision
      return unless prior

      validate_provenance
      validate_order if prior.source_updated_at && @observation.data[:source_updated_at]
    end

    def prior
      @prior ||= ::GameObservation.where(game: @game, accepted: true).order(:id).last
    end

    def validate_provenance
      hold('conflict', 'missing_accepted_provenance') unless prior
      previous = prior.attributes.values_at('provider', 'external_game_id', 'semantic_profile')
      incoming = @observation.data.values_at(:provider, :external_game_id, :semantic_profile)
      hold('conflict', 'provider_or_profile_conflict') unless previous == incoming
    end

    def validate_order
      incoming = @observation.data[:source_updated_at]&.then { |value| Time.iso8601(value) }
      previous = prior.source_updated_at
      hold('conflict', 'unknown_source_freshness') unless incoming && previous
      validate_timestamps(incoming, previous)
    end

    def validate_timestamps(incoming, previous)
      hold('stale', 'older_source_revision') if incoming < previous
      hold('conflict', 'equal_source_revision_conflict') if incoming == previous
    end

    def hold(outcome, reason)
      raise ObservationResolution::Held.new(outcome, reason)
    end
  end
end
