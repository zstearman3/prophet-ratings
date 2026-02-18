# frozen_string_literal: true

class GenerateSeasonRatingsJob < ApplicationJob
  queue_as :default

  ##
  # Generates and backfills ratings, predictions, and related data for a given season.
  # Removes existing ratings data for the current ratings configuration version, recalculates preseason and daily ratings,
  # updates team season metrics, generates predictions for each game, and finalizes completed games throughout the season.
  # @param [Integer] season_id - The ID of the season to process.
  def perform(season_id, run_preseason: true, enqueue_nightly_predictions: true)
    season = Season.find(season_id)
    clear_current_version_data!(season)

    Rails.logger.info { "Backfilling ratings for season: #{season.year}" }
    initialize_preseason_ratings!(season) if run_preseason

    backfill_season!(season)

    Rails.logger.info { "✅ Done backfilling ratings for season #{season.year}" }

    enqueue_nightly_predictions!(season) if enqueue_nightly_predictions
  end

  private

  def clear_current_version_data!(season)
    ratings_config_version = RatingsConfigVersion.ensure_current!
    season.predictions.where(ratings_config_version:).destroy_all
    season.team_rating_snapshots.where(ratings_config_version:).destroy_all
  end

  def initialize_preseason_ratings!(season)
    ProphetRatings::PreseasonInitializer.new(season).call
  end

  def backfill_season!(season)
    (season.start_date..season.end_date).each do |date|
      backfill_date!(season, date)
    end
  end

  def backfill_date!(season, date)
    Rails.logger.debug { "Backfilling for #{date}" }
    games = Game.where(start_time: date.all_day)
    ProphetRatings::OverallRatingsCalculator.new(season).call(as_of: date)
    games.each(&:generate_prediction!)
    games.each { |game| game.finalize if game.final? }
  end

  def enqueue_nightly_predictions!(season)
    GenerateNightlyPredictionsJob.perform_later(season.id)
  end
end
