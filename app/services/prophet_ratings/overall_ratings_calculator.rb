# frozen_string_literal: true

require 'pry'
module ProphetRatings
  class OverallRatingsCalculator
    def initialize(season)
      @season = season
      @acceptble_error = 100.0
    end

    def calculate_season_ratings
      @season.update_average_ratings

      TeamSeason.where(season: @season).update_all(
        adj_offensive_efficiency: @season.average_efficiency,
        adj_defensive_efficiency: @season.average_efficiency,
        adj_pace: @season.average_pace
      )

      iterate_over_ratings_calculations

      TeamSeason.where(season: @season).find_each do |s|
        s.update!(rating: s.adj_offensive_efficiency - s.adj_defensive_efficiency)
      end
    end

    private

    def iterate_over_ratings_calculations
      err = 0

      5.times do
        team_seasons = TeamSeason.includes(team_games: %i[game opponent_team_season]).where(season: @season)
        err += single_ratings_calculations(team_seasons)
        team_seasons.each(&:save)
      end
    end

    def single_ratings_calculations(team_seasons)
      err = 0

      team_seasons.each do |team_season|
        err += update_team_rankings(team_season)
      end

      err
    end

    def update_team_rankings(team_season)
      total_o_err = 0
      total_d_err = 0
      total_pace_err = 0
      total_weight = 0

      team_season.team_games.each_with_index do |team_game, i|
        next unless team_game.opponent_team_season

        err_calculator = ProphetRatings::GameErrorCalculator.new(
          team_game, team_season, team_game.opponent_team_season, team_game.game, @season
        )

        game_weight = i < 5 ? 1.2 : 1

        total_o_err += (err_calculator.offensive_error * game_weight)
        total_d_err += (err_calculator.defensive_error * game_weight)
        total_pace_err += (err_calculator.pace_error * game_weight)
        total_weight += game_weight
      end

      return 0 if total_weight.zero?

      team_season.assign_attributes(
        adj_offensive_efficiency: (team_season.adj_offensive_efficiency + (total_o_err / total_weight)),
        adj_defensive_efficiency: (team_season.adj_defensive_efficiency + (total_d_err / total_weight)),
        adj_pace: (team_season.adj_pace + (total_pace_err / total_weight))
      )

      total_o_err
    end
  end
end
