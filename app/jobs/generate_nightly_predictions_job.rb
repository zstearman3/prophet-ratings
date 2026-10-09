# frozen_string_literal: true

class GenerateNightlyPredictionsJob < ApplicationJob
  include PinnedModelVersion

  queue_as :default
  around_perform { |_job, block| Season.with_ratings_lock(&block) }

  LOOKAHEAD_DAYS = 7

  def perform(season_id = nil, as_of: Time.current, ratings_config_version_id: nil)
    season = resolve_season(season_id)
    return unless season

    version = RatingsConfigVersion.resolve(ratings_config_version_id)
    games_for_prediction(season, as_of:, ratings_config_version: version).find_each do |game|
      game.generate_prediction!(ratings_config_version: version)
    end
  end

  private

  def resolve_season(season_id)
    return Season.find_by(id: season_id) if season_id.present?

    Season.current
  end

  def games_for_prediction(season, as_of:, ratings_config_version:)
    season_games = season.games

    scheduled_next_week = season_games
                          .scheduled
                          .where(start_time: as_of..(as_of + LOOKAHEAD_DAYS.days))

    final_without_prediction = final_games_without_current_prediction(season_games, ratings_config_version)

    season_games
      .where(id: final_without_prediction.select(:id))
      .or(season_games.where(id: scheduled_next_week.select(:id)))
      .distinct
  end

  def final_games_without_current_prediction(games_scope, ratings_config_version)
    games_with_current_prediction = Prediction
                                    .where(game_id: games_scope.select(:id), ratings_config_version_id: ratings_config_version.id)
                                    .select(:game_id)

    games_scope.final.where.not(id: games_with_current_prediction)
  end
end
