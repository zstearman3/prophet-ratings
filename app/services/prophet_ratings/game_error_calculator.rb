# frozen_string_literal: true

module ProphetRatings
  class GameErrorCalculator
    def initialize(team_game, team_season, opponent_team_season, game, season = Season.current)
      @team_game = team_game
      @team_season = team_season
      @opponent_team_season = opponent_team_season
      @game = game
      @season = season

      @predictor = if team_game.home
                     GamePredictor.new(@team_season, @opponent_team_season, @game.neutral, season)
                   else
                     GamePredictor.new(@opponent_team_season, @team_season, @game.neutral, season)
                   end
    end

    def offensive_error
      @team_game.offensive_rating - predicted_ortg
    end

    def defensive_error
      @team_game.defensive_rating - predicted_drtg
    end

    def pace_error
      @game.pace - @predictor.expected_pace
    end

    private

    def predicted_ortg
      @team_game.home ? @predictor.home_expected_ortg : @predictor.away_expected_ortg
    end

    def predicted_drtg
      @team_game.home ? @predictor.home_expected_drtg : @predictor.away_expected_drtg
    end
  end
end
