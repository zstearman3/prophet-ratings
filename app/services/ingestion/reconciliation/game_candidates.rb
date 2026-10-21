# frozen_string_literal: true

module Ingestion
  module Reconciliation
    # Retains each source game ID and all conservative local pair candidates.
    class GameCandidates
      def initialize(season:, observations:, teams:, local:)
        @season = season
        @observations = observations
        @teams = teams.index_by { |row| row.fetch('external_id') }
        @local = local
      end

      def call
        @observations.group_by { |row| row['source_game_id'].to_s }.sort.map do |external_id, rows|
          GameCandidate.new(season: @season, external_id:, rows:, teams: @teams, local: @local).to_h
        end
      end
    end
  end
end
