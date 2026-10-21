# frozen_string_literal: true

module Importer
  # Legacy acquisition API; every public write reaches the canonical ingestion boundary.
  module GamesImporter
    TEAM_STAT_KEYS = Ingestion::GameObservation::STAT_KEYS
    BOX_SCORE_HEADER_SOURCE = 'sports_reference_box_score_header'

    class << self
      def import(data)
        data.map { |row| import_report(row) }
      end

      def import_game(row, season: nil)
        report = import_report(row, season:)
        Game.find_by(id: report[:game_id])
      end

      def import_report(row, season: nil)
        observation = Ingestion::SportsReferenceObservationAdapter.new(row, season:).call
        Ingestion::GameObservationImporter.new(observation:, season:).call
      end
    end
  end
end
