# frozen_string_literal: true

class GamesController < ApplicationController
  def show
    @game = Game.includes(
      home_team_game: %i[team team_season],
      away_team_game: %i[team team_season],
      predictions: %i[home_team_snapshot away_team_snapshot]
    ).find(params[:id])

    @home_team_game = @game.home_team_game
    @away_team_game = @game.away_team_game

    @prediction = @game.predictions.order(created_at: :desc).first
    @config = RatingsConfigVersion.current
  end
end
