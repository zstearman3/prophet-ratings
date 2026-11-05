# frozen_string_literal: true

module Ingestion
  # Recover the original provider values even when an accepted observation contains selected canonical values.
  class GameIssueSource
    def initialize(observation)
      @observation = observation
    end

    def payload
      raw = @observation.raw_payload
      return @observation.normalized_payload unless raw['provider'] == 'cbbd' && raw['format'].present?

      Cbbd::ImportObservation.new(raw, nil).payload.deep_stringify_keys
    end
  end
end
