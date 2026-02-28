# frozen_string_literal: true

class ResumeSeasonRatingsJob < ApplicationJob
  queue_as :default

  # Backfills ratings, predictions, and finalized game-derived values for a season.
  # Unlike GenerateSeasonRatingsJob, this does not clear existing predictions/snapshots.
  def perform(season_id, run_preseason: false, start_date: nil, end_date: nil)
    season = resolve_season(season_id)
    ratings_config_version = RatingsConfigVersion.ensure_current!
    date_range = backfill_date_range(season:, ratings_config_version:, start_date:, end_date:)
    return if date_range.nil?

    maybe_initialize_preseason!(season, ratings_config_version, run_preseason)

    Rails.logger.info do
      "Resuming ratings backfill for season #{season.year}: #{date_range.begin}..#{date_range.end}"
    end

    backfill_date_range!(season, date_range)

    Rails.logger.info { "✅ Done resumable ratings backfill for season #{season.year}" }
  end

  private

  def resolve_season(season)
    return season if season.is_a?(Season)

    Season.find(season)
  end

  def backfill_date_range(season:, ratings_config_version:, start_date:, end_date:)
    backfill_end_date = [coerce_date(end_date) || season.end_date, season.end_date].min
    backfill_start_date = coerce_date(start_date) || resume_start_date(season, ratings_config_version)
    backfill_start_date = [backfill_start_date, season.start_date].max

    if backfill_start_date > backfill_end_date
      Rails.logger.info do
        "Skipping resumable ratings backfill for #{season.year}: computed empty range " \
          "(start=#{backfill_start_date}, end=#{backfill_end_date})"
      end
      return nil
    end

    backfill_start_date..backfill_end_date
  end

  def resume_start_date(season, ratings_config_version)
    latest_snapshot_date = season.team_rating_snapshots.where(ratings_config_version:).maximum(:snapshot_date)
    latest_snapshot_date || season.start_date
  end

  def should_initialize_preseason?(season, ratings_config_version)
    season.team_rating_snapshots.where(ratings_config_version:).none?
  end

  def maybe_initialize_preseason!(season, ratings_config_version, run_preseason)
    return unless run_preseason && should_initialize_preseason?(season, ratings_config_version)

    initialize_preseason_ratings!(season)
  end

  def backfill_date_range!(season, date_range)
    date_range.each do |date|
      Rails.logger.debug { "Backfilling for #{date}" }
      games = season.games.where(start_time: date.all_day)
      ProphetRatings::OverallRatingsCalculator.new(season).call(as_of: date)
      games.each(&:generate_prediction!)
      games.each { |game| game.finalize if game.final? }
    end
  end

  def initialize_preseason_ratings!(season)
    ProphetRatings::PreseasonInitializer.new(season).call
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
