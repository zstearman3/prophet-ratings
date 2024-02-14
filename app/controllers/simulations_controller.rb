# frozen_string_literal: true

class SimulationsController < ApplicationController
  before_action :set_cache_headers

  def game
    @team_options = TeamSeason.includes(:team).where(season: Season.current)
                              .order('teams.school asc').map do |s|
      [s.team.school, s.id]
    end

    @home_team_season = TeamSeason.find_by(id: simulations_params[:home_team_id])
    @away_team_season = TeamSeason.find_by(id: simulations_params[:away_team_id])
    @neutral = simulations_params[:neutral] == '1'

    return unless @home_team_season && @away_team_season

    @predictor = ProphetRatings::GamePredictor.new(@home_team_season, @away_team_season, @neutral)
    scores = @predictor.simulated_scores

    @home_score = scores[:home_score]
    @away_score = scores[:away_score]
  end

  private

  def simulations_params
    params.permit(
      :home_team_id,
      :away_team_id,
      :neutral
    )
  end

  def set_cache_headers
    response.headers["Cache-Control"] = "no-cache, no-store"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "Mon, 01 Jan 1990 00:00:00 GMT"
  end
end
