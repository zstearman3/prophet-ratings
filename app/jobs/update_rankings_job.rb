# frozen_string_literal: true

class UpdateRankingsJob < ApplicationJob
  queue_as :default

  def perform(season = Season.current)
    TeamSeason.includes(team_games: %i[game opponent_game]).where(season:)
  end
end
