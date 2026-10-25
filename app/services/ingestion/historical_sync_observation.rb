# frozen_string_literal: true

module Ingestion
  # Isolate expected CBBD row holds; unexpected errors still abort the enclosing date.
  class HistoricalSyncObservation
    def initialize(row, season)
      @row = row
      @season = season
    end

    def call
      Game.transaction(requires_new: true) { import_result }
    rescue HistoricalSyncDay::ReconciliationError => error
      error.retained_game_report
    end

    private

    def import_result
      result = Cbbd::ImportObservation.new(@row, @season).call
      validate_result(result)
      result
    end

    def validate_result(result)
      return unless GameSyncProvider.held?(result)

      report = { imported_rows: result[:applied] ? 1 : 0, games: [result] }
      raise HistoricalSyncDay::ReconciliationError.new(report, rollback_reason: 'game_rolled_back')
    end
  end
end
