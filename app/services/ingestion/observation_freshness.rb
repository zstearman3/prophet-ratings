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

    def validate_projection(identical:)
      return if authority.empty?

      validate_provenance
      validate_order if !identical && prior_order&.source_updated_at && @observation.data[:source_updated_at]
    end

    private

    def validate_pending_revision
      return if authority.empty?

      validate_provenance
      validate_order if prior_order&.source_updated_at && @observation.data[:source_updated_at]
    end

    def prior
      @prior ||= authority.order(accepted: :desc, id: :desc).first
    end

    def authority
      ::GameObservation.where(game: @game, accepted: true)
                       .or(::GameObservation.where(game: @game, outcome: 'projected'))
                       .or(::GameObservation.where(game: @game, outcome: 'unchanged', reason: ObservationAudit::PROJECTION_REASON))
    end

    def prior_order
      @prior_order ||= authority.where(provider: prior.provider, semantic_profile: prior.semantic_profile)
                                .where.not(source_updated_at: nil).order(:source_updated_at, :id).last
    end

    def provenance_keys
      return %i[provider semantic_profile] if @observation.schedule_projection? || prior.external_game_id.blank?

      %i[provider external_game_id semantic_profile]
    end

    def validate_provenance
      hold('conflict', 'missing_accepted_provenance') unless prior
      keys = provenance_keys
      previous = prior.attributes.values_at(*keys.map(&:to_s))
      incoming = @observation.data.values_at(*keys)
      hold('conflict', 'provider_or_profile_conflict') unless previous == incoming
    end

    def validate_order
      incoming = @observation.data[:source_updated_at]&.then { |value| Time.iso8601(value) }
      previous = prior_order&.source_updated_at
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
