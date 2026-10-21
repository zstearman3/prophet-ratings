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
        coverage = source_box_coverage(observation)
        Ingestion::GameObservationImporter.new(observation:, season:).call.merge(final_box: coverage)
      end

      # Inspect a copy before canonical equality can conceal missing current-source inputs.
      def source_box_coverage(observation)
        source = Ingestion::GameObservation.new(observation.data).validate
        return 'not_final' unless source.data[:source_status] == 'final'
        return 'missing' unless source.strict_final?

        complete_source_box(source)
      rescue Ingestion::GameObservation::Invalid
        'invalid'
      end

      def complete_source_box(source)
        source.validate_duration
        'complete'
      end
    end
  end
end
