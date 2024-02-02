class TeamSeasonsController < ApplicationController
  before_action :set_season

  def ratings
    @team_seasons = TeamSeason.includes(:team).where(season: @season).order(rating: :desc)
  end

  private

  def ratings_params
    params.permit(:season)
  end

  def set_season
    @season = ratings_params[:season] ? Season.find_by(year: ratings_params[:season]) : Season.current
  end
end
