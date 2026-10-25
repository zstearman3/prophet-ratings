# frozen_string_literal: true

class SyncDailyGamesJob < HeavyJob
  rescue_from Ingestion::GameSyncProvider::Incomplete do |error|
    raise error
  end

  def perform(date = Game.current_schedule_date - 1.day, season_id: nil, **options)
    @options = options
    date = Ingestion::HistoricalSyncWindow.parse_date(date)
    season = season_id && Season.find(season_id)
    season ? provider_sync(season, date) : unscoped_sync(date)
  end

  private

  attr_reader :options

  def unscoped_sync(date)
    policy = Ingestion::GameSyncPolicy.new(options[:provider], options.fetch(:provider_options, {}))
    unless policy.provider == 'sports_reference'
      raise Ingestion::GameSyncProvider::Incomplete, { complete: false, error: 'Explicit season_id required' }
    end

    Ingestion::GamesIngestionService.new(date:).call
  end

  def provider_sync(season, date)
    report = Ingestion::GameSyncRun.new(season:, dates: [date], resume: false, **options).call
    validate_report(report)
    report[:days].first
  end

  def validate_report(report)
    return if report[:complete]
    raise Ingestion::GameSyncProvider::Incomplete, report if report.dig(:scope, :provider) == 'cbbd'

    raise SyncFullSeasonGamesJob::IncompleteSync, report
  end
end
