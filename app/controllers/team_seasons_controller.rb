# frozen_string_literal: true

class TeamSeasonsController < ApplicationController
  before_action :set_season

  def ratings
    sort_column = permitted_sort_columns.include?(params[:sort]) ? params[:sort] : 'rating'
    direction = %w[asc desc].include?(params[:direction]) ? params[:direction] : 'desc'

    @team_seasons = TeamSeason
                    .includes(:team)
                    .where(season: @season)
    @team_seasons =
      if sort_column == 'team.school'
        # Order by associated teams.school using Arel to avoid SQL interpolation
        @team_seasons.references(:team).order(Team.arel_table[:school].public_send(direction))
      else
        # Order by whitelisted TeamSeason column using hash syntax
        @team_seasons.order(sort_column.to_sym => direction.to_sym)
      end
  end

  private

  def ratings_params
    params.permit(:season)
  end

  def set_season
    @season = ratings_params[:season] ? Season.find_by(year: ratings_params[:season]) : Season.current
  end

  def permitted_sort_columns
    %w[
      rating
      adj_offensive_efficiency
      adj_defensive_efficiency
      adj_pace
      adj_turnover_rate
      adj_offensive_rebound_rate
      adj_free_throw_rate
      adj_three_pt_proficiency
      adj_three_pt_proficiency_allowed
      adj_effective_fg_percentage
      adj_effective_fg_percentage_allowed
      adj_defensive_rebound_rate
      adj_turnover_rate_forced
      offensive_efficiency
      defensive_efficiency
      pace
      effective_fg_percentage
      free_throw_rate
      offensive_rebound_rate
      turnover_rate
      home_offense_boost
      home_defense_boost
      total_home_boost
      offensive_efficiency_volatility
      defensive_efficiency_volatility
      pace_volatility
      offensive_efficiency_std_dev
      defensive_efficiency_std_dev
      team.school
    ]
  end
end
