# frozen_string_literal: true

module Importer
  # Reconciliation reports are the canonical boundary's outcomes, including audit-only rows.
  class ScheduleRowImporter
    def initialize(season:, row:)
      @season = season
      @row = row
    end

    def call
      GamesImporter.import_report(@row, season: @season)
    end
  end
end
