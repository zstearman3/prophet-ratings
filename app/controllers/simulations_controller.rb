# frozen_string_literal: true

class SimulationsController < ApplicationController
  before_action :set_cache_headers, :set_current_options

  def game
    @team_options = TeamSeason.includes(:team).where(season: Season.current)
                              .order('teams.school asc').map do |s|
      [s.team.school, s.id]
    end

    @current_prediction = {}

    return unless @current_options[:home_team_season] && @current_options[:away_team_season]

    @current_prediction[:predictor] = ProphetRatings::GamePredictor.new(**@current_options)
    scores = @current_prediction[:predictor].simulated_scores

    @current_prediction[:home_score] = scores[:home_score]
    @current_prediction[:away_score] = scores[:away_score]
  end

  private

  def simulations_params
    params.permit(
      :home_team_id,
      :away_team_id,
      :neutral,
      :upset_modifier
    )
  end

  def set_cache_headers
    response.headers['Cache-Control'] = 'no-cache, no-store'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = 'Mon, 01 Jan 1990 00:00:00 GMT'
  end

  def set_current_options
    @current_options = {}

    @current_options[:home_team_season] = TeamSeason.find_by(id: simulations_params[:home_team_id])
    @current_options[:away_team_season] = TeamSeason.find_by(id: simulations_params[:away_team_id])
    @current_options[:neutral] = simulations_params[:neutral] == '1'
    @current_options[:upset_modifier] = simulations_params[:upset_modifier] || 1.0
  end
end
