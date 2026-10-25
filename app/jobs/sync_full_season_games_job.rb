# frozen_string_literal: true

class SyncFullSeasonGamesJob < HeavyJob
  # Carries the complete per-date report through async failures and operator exits.
  class IncompleteSync < StandardError
    attr_reader :report

    def initialize(report)
      @report = report
      super("Historical sync incomplete: retry dates #{report[:failed_dates].join(', ')}")
    end
  end

  rescue_from Ingestion::GameSyncProvider::Incomplete do |error|
    raise error
  end

  def perform(season, start_date: nil, end_date: nil, resume: true, **options)
    dedupe = options.delete(:dedupe)
    target = season.is_a?(Season) ? season : Season.find(season)
    dates = Ingestion::HistoricalSyncWindow.new(season: target, start_date:, end_date:).dates
    report = Ingestion::GameSyncRun.new(season: target, dates:, resume:, **options).call
    Rails.logger.info { "Historical sync: #{report.to_json}" }
    validate_report(report)
    RepairDuplicateGamesJob.perform_later(season_id: target.id, apply: true) if dedupe
    report
  end

  private

  def validate_report(report)
    return if report[:complete]

    raise Ingestion::GameSyncProvider::Incomplete, report if report.dig(:scope, :provider) == 'cbbd'

    raise IncompleteSync, report
  end
end
