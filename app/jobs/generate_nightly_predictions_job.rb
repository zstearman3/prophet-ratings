# frozen_string_literal: true

class GenerateNightlyPredictionsJob < ApplicationJob
  queue_as :default

  LOOKAHEAD_DAYS = 7

  def perform(season_id = nil, as_of: Time.current)
    season = resolve_season(season_id)
    return unless season

    games_for_prediction(season, as_of:).find_each(&:generate_prediction!)
  end

  private

  def resolve_season(season_id)
    return Season.find_by(id: season_id) if season_id.present?

    Season.current || Season.last
  end

  def games_for_prediction(season, as_of:)
    season_games = season.games

    scheduled_next_week = season_games
                          .scheduled
                          .where(start_time: as_of..(as_of + LOOKAHEAD_DAYS.days))

    final_without_prediction = final_games_without_current_prediction(season_games)

    season_games
      .where(id: final_without_prediction.select(:id))
      .or(season_games.where(id: scheduled_next_week.select(:id)))
      .distinct
  end

  def final_games_without_current_prediction(games_scope)
    ratings_config_version = RatingsConfigVersion.current
    return games_scope.final.where.missing(:predictions) unless ratings_config_version

    games_with_current_prediction = Prediction
                                    .where(game_id: games_scope.select(:id), ratings_config_version_id: ratings_config_version.id)
                                    .select(:game_id)

    games_scope.final.where.not(id: games_with_current_prediction)
  end
end
