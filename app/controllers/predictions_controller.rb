class PredictionsController < ApplicationController
  def game
    @team_options = TeamSeason.includes(:team).where(season: Season.current)
    .order("teams.school asc").map do |s|
        [s.team.school, s.id]
    end

    @home_team_season = TeamSeason.find_by(id: predictions_params[:home_team_id])
    @away_team_season = TeamSeason.find_by(id: predictions_params[:away_team_id])

    @predictor = ProphetRatings::GamePredictor.new(@home_team_season, @away_team_season, predictions_params[:neutral] == '1') if @home_team_season && @away_team_season
  end

  private

  def predictions_params
    params.permit(
      :home_team_id,
      :away_team_id,
      :neutral,
    )
  end
end
