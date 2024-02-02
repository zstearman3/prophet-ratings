# frozen_string_literal: true

class UpdateRankingsJob < ApplicationJob
  queue_as :default

  def perform(season = Season.current)
    season.update_average_ratings
    teams = TeamSeason.includes(team_games: [game: %i[away_team_game home_team_game]]).merge(TeamGame.unscoped).where(season:)
    teams_hash = format_teams(teams)

    teams.each_with_index do |team, _i|
      ProphetRatings::OverallRatingsCalculator.new(team, teams_hash, team.team_games).calculate_season_ratings
    end
  end

  private

  def format_teams(teams)
    teams.to_h do |t|
      [t.team_id,
       {
         adj_offensive_efficiency: t.adj_offensive_efficiency,
         adj_defensive_efficiency: t.adj_defensive_efficiency,
         adj_pace: t.adj_pace
       }]
    end
  end
end
