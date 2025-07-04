# frozen_string_literal: true

class GenerateSeasonRatingsJob < ApplicationJob
  queue_as :default

  ##
  # Generates and backfills ratings, predictions, and related data for a given season.
  # Removes existing ratings data for the current ratings configuration version, recalculates preseason and daily ratings, updates team season metrics, generates predictions for each game, and finalizes completed games throughout the season.
  # @param [Integer] season_id - The ID of the season to process.
  def perform(season_id)
    season = Season.find(season_id)
    ratings_config_version = RatingsConfigVersion.ensure_current!
    season.predictions.where(ratings_config_version:).destroy_all
    season.team_rating_snapshots.where(ratings_config_version:).destroy_all

    start_date = season.start_date

    Rails.logger.info { "Backfilling ratings for season: #{season.year}" }
    ProphetRatings::PreseasonRatingsCalculator.new(season).call
    season.team_seasons.each do |ts|
      ts.update(
        rating: ts.preseason_adj_offensive_efficiency - ts.preseason_adj_defensive_efficiency,
        adj_offensive_efficiency: ts.preseason_adj_offensive_efficiency,
        adj_defensive_efficiency: ts.preseason_adj_defensive_efficiency,
        adj_pace: ts.preseason_adj_pace
      )
    end

    (start_date..season.end_date).each do |date|
      Rails.logger.debug { "Backfilling for #{date}" }
      games = Game.where(start_time: date.all_day)
      ProphetRatings::OverallRatingsCalculator.new(season).call(as_of: date)
      games.each(&:generate_prediction!)
      games.each { |game| game.finalize if game.final? }
    end

    Rails.logger.info { "✅ Done backfilling ratings for season #{season.year}" }
  end
end
