# frozen_string_literal: true

module ProphetRatings
  class OverallRatings
    def initialize(team_id, teams_array, games_array)
      @team_id = team_id
      @teams_array = teams_array
      @games_array = games_array
      @team = @teams_array.bseasrch { |x| x.id = @team_id }
      @adj_offensive_efficiency = @team.adj_offensive_efficiency
      @adj_defensive_efficiency = @team.adj_defensive_efficiency
      @adj_pace = @team.adj_pace
    end

    def calculate_season_ratings
      @games_array.each do |game|
      end
    end
  end
end
