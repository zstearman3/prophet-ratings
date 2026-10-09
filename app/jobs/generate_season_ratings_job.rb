# frozen_string_literal: true

class GenerateSeasonRatingsJob < ApplicationJob
  include PinnedModelVersion

  queue_as :default
  around_perform { |_job, block| Season.with_ratings_lock(&block) }

  # Delete/rebuild only an explicit season, config and historical date window.
  # A single transaction restores deleted outputs and live values on failure.
  def perform(season_id, rebuild: false, **options)
    date_range = options[:date_range]
    run_preseason = options.fetch(:run_preseason, false)
    raise ArgumentError, 'Destructive rebuild requires rebuild: true and an explicit date_range' unless rebuild && date_range

    season = Season.find(season_id)
    raise ArgumentError, 'Rebuild date_range must be an inclusive Date range' unless date_range.is_a?(Range) && !date_range.exclude_end?

    validate_rebuild_range!(season, date_range.begin, date_range.end)
    if run_preseason && date_range.begin != season.start_date
      raise ArgumentError, 'Preseason reset requires a rebuild starting at season.start_date'
    end

    Season.transaction do
      ratings_config_version = RatingsConfigVersion.resolve(options[:ratings_config_version_id])
      clear_current_version_data!(season, date_range, ratings_config_version)
      ProphetRatings::PreseasonInitializer.new(season, ratings_config_version: ratings_config_version).reset if run_preseason
      ResumeSeasonRatingsJob.new.perform(season.id, start_date: date_range.begin, end_date: date_range.end,
                                                    ratings_config_version_id: ratings_config_version.id)
    end
  end

  def self.predictions_in_range(season, date_range, ratings_config_version)
    games = season.games.where(start_time: Game.schedule_day_range(date_range.begin).begin..Game.schedule_day_range(date_range.end).end)
    season.predictions.where(ratings_config_version:, game_id: games.select(:id))
  end

  private

  def validate_rebuild_range!(season, first, last)
    raise ArgumentError, 'Rebuild boundaries must be Dates' unless first.is_a?(Date) && last.is_a?(Date)

    allowed_range = season.start_date..[season.end_date, Game.current_schedule_date].min
    return if allowed_range.cover?(first) && allowed_range.cover?(last) && first <= last

    raise ArgumentError, 'Rebuild range must be within the season and must not include future dates'
  end

  def clear_current_version_data!(season, date_range, ratings_config_version)
    snapshots = season.team_rating_snapshots.where(ratings_config_version:, snapshot_date: date_range)
    predictions = self.class.predictions_in_range(season, date_range, ratings_config_version)
    destroy_rebuild_outputs!(snapshots, predictions)
  end

  def destroy_rebuild_outputs!(snapshots, predictions)
    assert_snapshot_dependencies!(snapshots, predictions)
    predictions.destroy_all
    snapshots.destroy_all
  end

  def assert_snapshot_dependencies!(snapshots, predictions)
    snapshot_ids = snapshots.select(:id)
    dependents = Prediction.where(home_team_snapshot_id: snapshot_ids).or(Prediction.where(away_team_snapshot_id: snapshot_ids))
    return unless dependents.where.not(id: predictions.select(:id)).exists?

    raise ArgumentError, 'Window snapshots are used by predictions outside the rebuild scope; review and widen the explicit window.'
  end
end
