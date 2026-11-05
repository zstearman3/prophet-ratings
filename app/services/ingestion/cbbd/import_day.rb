# frozen_string_literal: true

module Ingestion
  module Cbbd
    # Preserve previously committed rows if a later game encounters an operational failure.
    class ImportDay
      def initialize(season, rows)
        @season = season
        @rows = rows
        @games = []
      end

      def call
        @rows.each { |row| retain_result(row) }
        GameSyncResult.new(report).call
      rescue StandardError => error
        raise GameSyncProvider::Incomplete, report.merge(processing_complete: false, operational_failure: true,
                                                         error_class: error.class.name)
      end

      private

      def retain_result(row)
        @games << HistoricalSyncObservation.new(row, @season).call
      end

      def report
        committed = @games.count { |game| game[:applied] }
        { games: @games, imported_rows: committed, committed_rows: committed }
      end
    end
  end
end
