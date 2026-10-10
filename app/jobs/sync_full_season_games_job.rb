# frozen_string_literal: true

class SyncFullSeasonGamesJob < ApplicationJob
  queue_as :default

  # Carries the complete per-date report through async failures and operator exits.
  class IncompleteSync < StandardError
    attr_reader :report

    def initialize(report)
      @report = report
      super("Historical sync incomplete: retry dates #{report[:failed_dates].join(', ')}")
    end
  end

  def perform(season, start_date: nil, end_date: nil, resume: true, dedupe: false)
    @sync_season = season.is_a?(Season) ? season : Season.find(season)
    dates = Ingestion::HistoricalSyncWindow.new(season: sync_season, start_date:, end_date:).dates
    days = dates.map { |date| Ingestion::HistoricalSyncDay.new(season: sync_season, date:, resume:).call }
    @failed_dates = days.select { |day| day[:error] }.pluck(:date)
    report = { year: sync_season.year, days:, failed_dates:, retry_window: }
    Rails.logger.info { "Historical sync: #{report.to_json}" }
    raise IncompleteSync, report if failed_dates.any?

    RepairDuplicateGamesJob.perform_later(season_id: sync_season.id, apply: true) if dedupe
    report
  end

  private

  attr_reader :failed_dates, :sync_season

  def retry_window
    return if failed_dates.empty?

    { start_date: failed_dates.min, end_date: failed_dates.max, resume: true }
  end
end
