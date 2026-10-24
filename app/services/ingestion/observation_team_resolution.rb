# frozen_string_literal: true

module Ingestion
  # Only CBBD may retain a name-only opponent outside the selected rated membership.
  class ObservationTeamResolution
    def initialize(resolution, side)
      @provider = resolution.observation.data[:provider]
      @name, @external_id = side.values_at(:name, :external_team_id)
      @candidates = Team.matching_school_or_alias(@name).to_a
    end

    def call
      return mapped_team if @external_id
      return if @provider == 'cbbd' && @candidates.empty?

      ObservationResolution.unique_team(@candidates, @name)
    end

    private

    def mapped_team
      team = TeamExternalIdentity.find_by(provider: @provider, external_id: @external_id)&.team
      return unmapped_team unless team

      if @candidates.any? { |candidate| candidate != team }
        raise ObservationResolution::Held.new('conflict', 'participant_label_identity_conflict')
      end

      team
    end

    def unmapped_team
      if @provider == 'cbbd'
        return if @candidates.empty?

        ObservationResolution.unique_team(@candidates, @name)
      end
      raise ObservationResolution::Held.new('unmatched', 'unmapped_external_team_identity', participants: [@name])
    end
  end
end
