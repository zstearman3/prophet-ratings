# frozen_string_literal: true

module ProphetRatings
  class OverallRatingsCalculator
    def initialize(team, teams_array, games_array)
      @team = team
      @teams_array = teams_array
      @games_array = games_array
      @adj_offensive_efficiency = @team.adj_offensive_efficiency
      @adj_defensive_efficiency = @team.adj_defensive_efficiency
      @adj_pace = @team.adj_pace
    end

    def calculate_season_ratings
      @games_array.each do |game|
        find_opponent_game(game)
      end
    end

    private

    def find_opponent_game(game)
      if game.game.home_team_game_id == game.id
        game.game.away_team_game
      else
        game.game.home_team_game
      end
    end
  end
end
