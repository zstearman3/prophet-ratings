# frozen_string_literal: true

class UpdateRankingsJob < ApplicationJob
  queue_as :default

  def perform(season = Season.current)
    teams = TeamSeason.includes(team_games: %i[game opponent_game]).where(season:)
    teams_hash = format_teams(teams)

    team.each do |team|
      ProphetRatings::OverallRatings.new(team, teams_hash, team.team_games).calculate_season_ratings
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
