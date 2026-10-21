# frozen_string_literal: true

class SyncNightlyGamesJob < ApplicationJob
  queue_as :default

  PAST_LOOKBACK_DAYS = 2

  rescue_from Ingestion::GameSyncProvider::Incomplete do |error|
    raise error
  end

  def perform(season_id = nil, enqueue_rankings: nil, past_lookback_days: nil, future_end_date: nil,
              **options)
    season = resolve_season(season_id)
    return unless season

    @schedule_date = Game.current_schedule_date
    policy = Ingestion::GameSyncPolicy.new(options[:provider], options.fetch(:provider_options, {}))
    validate_policy(policy, lookback: past_lookback_days, future: future_end_date, rankings: enqueue_rankings)
    lookback = past_lookback_days || PAST_LOOKBACK_DAYS
    @windows = sync_windows(season, past_lookback_days: lookback, future_end_date:)
    @report = sync_provider_dates(season, options)
    enqueue_ready_rankings(season.id, enqueue_rankings)
    validate_report
    report
  rescue StandardError => error
    raise unless policy&.provider == 'cbbd'
    raise if error.is_a?(Ingestion::GameSyncProvider::Incomplete)

    raise Ingestion::GameSyncProvider::Incomplete, { complete: false, scope: policy.scope, error_class: error.class.name }
  end

  private

  attr_reader :schedule_date, :windows, :report

  def validate_policy(policy, request)
    lookback = request[:lookback]
    raise ArgumentError, 'past_lookback_days must be a nonnegative integer' if lookback && (!lookback.is_a?(Integer) || lookback.negative?)
    return unless policy.provider == 'cbbd'
    raise ArgumentError, 'CBBD nightly requires explicit past_lookback_days and future_end_date' unless lookback && request[:future]
    raise ArgumentError, 'CBBD nightly does not automatically enqueue rankings' if request[:rankings]
  end

  def sync_provider_dates(season, options)
    report = Ingestion::GameSyncRun.new(season:, dates: windows.values.flatten, resume: false, **options).call
    past_failed, future_failed = report.fetch(:failed_dates).partition { |date| date < schedule_date }
    report.merge(schedule_date:, past_dates: windows[:past], future_dates: windows[:future],
                 past_complete: past_failed.empty?, future_complete: future_failed.empty?,
                 past_failed_dates: past_failed, future_failed_dates: future_failed)
  end

  def enqueue_ready_rankings(season_id, requested)
    return unless [true, nil].include?(requested)
    return if report.dig(:scope, :provider) == 'cbbd'
    return UpdateRankingsJob.perform_later(season_id) if report[:complete]
    return unless report[:past_dates].any? && report[:past_complete]

    UpdateRankingsJob.perform_later(season_id, sync_schedule_date: schedule_date)
  end

  def validate_report
    return if report[:complete]
    raise Ingestion::GameSyncProvider::Incomplete, report if report.dig(:scope, :provider) == 'cbbd' || report[:past_complete]

    raise SyncFullSeasonGamesJob::IncompleteSync, report
  end

  def resolve_season(season_id)
    return Season.find(season_id) if season_id.present?

    Season.current
  end

  def sync_windows(season, past_lookback_days:, future_end_date:)
    { past: recently_completed_or_stale_dates(season, past_lookback_days:),
      future: upcoming_scheduled_dates(season, future_end_date:) }
  end

  def recently_completed_or_stale_dates(season, past_lookback_days:)
    range_to_a(
      [schedule_date - past_lookback_days.days, season.start_date].max,
      [schedule_date - 1.day, season.end_date].min
    )
  end

  def upcoming_scheduled_dates(season, future_end_date:)
    sync_end_date = coerce_date(future_end_date) || season.end_date
    if future_end_date && !(season.start_date..season.end_date).cover?(sync_end_date)
      raise ArgumentError, 'Future end date must be inside the target season'
    end
    raise ArgumentError, 'Future end date precedes today' if future_end_date && sync_end_date < schedule_date

    range_to_a(
      [schedule_date, season.start_date].max,
      sync_end_date
    )
  end

  def range_to_a(start_date, end_date)
    return [] if start_date > end_date

    (start_date..end_date).to_a
  end

  def coerce_date(value)
    Ingestion::HistoricalSyncWindow.parse_date(value) if value
  end
end
