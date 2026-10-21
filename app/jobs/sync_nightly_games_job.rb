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

    policy = Ingestion::GameSyncPolicy.new(options[:provider], options.fetch(:provider_options, {}))
    validate_policy(policy, lookback: past_lookback_days, future: future_end_date, rankings: enqueue_rankings)
    lookback = past_lookback_days || PAST_LOOKBACK_DAYS
    dates = sync_dates(season, past_lookback_days: lookback, future_end_date:)
    cbbd = policy.provider == 'cbbd'
    target_id = season.id
    report = sync_provider_dates(season, dates, options)
    rankings = [true, nil].include?(enqueue_rankings)
    UpdateRankingsJob.perform_later(target_id) if rankings && !cbbd
    report
  rescue StandardError => error
    raise unless policy&.provider == 'cbbd'
    raise if error.is_a?(Ingestion::GameSyncProvider::Incomplete)

    raise Ingestion::GameSyncProvider::Incomplete, { complete: false, scope: policy.scope, error_class: error.class.name }
  end

  private

  def validate_policy(policy, request)
    lookback = request[:lookback]
    raise ArgumentError, 'past_lookback_days must be a nonnegative integer' if lookback && (!lookback.is_a?(Integer) || lookback.negative?)
    return unless policy.provider == 'cbbd'
    raise ArgumentError, 'CBBD nightly requires explicit past_lookback_days and future_end_date' unless lookback && request[:future]
    raise ArgumentError, 'CBBD nightly does not automatically enqueue rankings' if request[:rankings]
  end

  def sync_provider_dates(season, dates, options)
    report = Ingestion::GameSyncRun.new(season:, dates:, resume: false, **options).call
    unless report[:complete]
      raise Ingestion::GameSyncProvider::Incomplete, report if report.dig(:scope, :provider) == 'cbbd'

      raise SyncFullSeasonGamesJob::IncompleteSync, report
    end

    report
  end

  def resolve_season(season_id)
    return Season.find(season_id) if season_id.present?

    Season.current
  end

  def sync_dates(season, past_lookback_days:, future_end_date:)
    recently_completed_or_stale_dates(season, past_lookback_days:) +
      upcoming_scheduled_dates(season, future_end_date:)
  end

  def recently_completed_or_stale_dates(season, past_lookback_days:)
    range_to_a(
      [Game.current_schedule_date - past_lookback_days.days, season.start_date].max,
      [Game.current_schedule_date - 1.day, season.end_date].min
    )
  end

  def upcoming_scheduled_dates(season, future_end_date:)
    sync_end_date = coerce_date(future_end_date) || season.end_date
    if future_end_date && !(season.start_date..season.end_date).cover?(sync_end_date)
      raise ArgumentError, 'Future end date must be inside the target season'
    end
    raise ArgumentError, 'Future end date precedes today' if future_end_date && sync_end_date < Game.current_schedule_date

    range_to_a(
      [Game.current_schedule_date, season.start_date].max,
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
