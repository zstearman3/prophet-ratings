# frozen_string_literal: true

module Ingestion
  module Reconciliation
    # Exact provider keys precede the union of exact canonical names and aliases.
    class TeamCandidates
      def initialize(season:, observations:)
        @season = season
        @sides = observations.flat_map { |row| row.values_at('home', 'away') }
      end

      def call
        grouped = @sides.group_by { |side| side['source_team_id'].to_s }
        grouped.sort.map { |external_id, sides| TeamCandidate.new(@season, external_id, sides, grouped).to_h }
      end
    end
  end
end
