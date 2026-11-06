# frozen_string_literal: true

module Ingestion
  # Isolate expected CBBD row holds; unexpected errors still abort the enclosing date.
  class HistoricalSyncObservation
    def initialize(row, season)
      @row = row
      @season = season
    end

    def call
      import_transaction
    rescue HistoricalSyncDay::ReconciliationError => error
      retain_rejection(error)
    end

    private

    def import_transaction
      Game.transaction(requires_new: true) { import_result }
    end

    def retain_rejection(error)
      Game.transaction(requires_new: true) { with_issues(error.retained_game_report) }
    end

    def import_result
      result = Cbbd::ImportObservation.new(@row, @season).call
      validate_result(result)
      with_issues(result)
    end

    def with_issues(result)
      GameIssueRecorder.new(season: @season, report: result).report
    end

    def validate_result(result)
      return unless GameSyncProvider.held?(result)

      report = { imported_rows: result[:applied] ? 1 : 0, games: [result] }
      raise HistoricalSyncDay::ReconciliationError.new(report, rollback_reason: 'game_rolled_back')
    end
  end
end
