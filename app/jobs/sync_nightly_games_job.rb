# frozen_string_literal: true

class SyncNightlyGamesJob < ApplicationJob
  queue_as :default

  PAST_LOOKBACK_DAYS = 2

  def perform(season_id = nil, enqueue_rankings: true, past_lookback_days: PAST_LOOKBACK_DAYS, future_end_date: nil)
    season = resolve_season(season_id)
    return unless season

    sync_dates(season, past_lookback_days:, future_end_date:).each do |date|
      SyncDailyGamesJob.perform_now(date)
    end

    return unless enqueue_rankings

    UpdateRankingsJob.perform_later(season.id)
  end

  private

  def resolve_season(season_id)
    return Season.find_by(id: season_id) if season_id.present?

    Season.current || Season.last
  end

  def sync_dates(season, past_lookback_days:, future_end_date:)
    recently_completed_or_stale_dates(season, past_lookback_days:) +
      upcoming_scheduled_dates(season, future_end_date:)
  end

  def recently_completed_or_stale_dates(season, past_lookback_days:)
    range_to_a(
      [Time.zone.today - past_lookback_days.days, season.start_date].max,
      [Time.zone.today - 1.day, season.end_date].min
    )
  end

  def upcoming_scheduled_dates(season, future_end_date:)
    sync_end_date = [coerce_date(future_end_date) || season.end_date, season.end_date].min

    range_to_a(
      [Time.zone.today, season.start_date].max,
      sync_end_date
    )
  end

  def range_to_a(start_date, end_date)
    return [] if start_date > end_date

    (start_date..end_date).to_a
  end

  def coerce_date(value)
    return value if value.is_a?(Date)
    return value.to_date if value.respond_to?(:to_date)
    return if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
