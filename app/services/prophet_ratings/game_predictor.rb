# frozen_string_literal: true

module ProphetRatings
  class GamePredictor
    def initialize(home_team_season, away_team_season, neutral = false, season = Season.current)
      @home_team_season = home_team_season
      @away_team_season = away_team_season
      @neutral = neutral
      @season = season
    end

    def home_expected_ortg
      (@home_team_season.adj_offensive_efficiency - @season.average_efficiency) +
        (@away_team_season.adj_defensive_efficiency - @season.average_efficiency) +
        @season.average_efficiency + home_court_advantage
    end

    def away_expected_ortg
      (@away_team_season.adj_offensive_efficiency - @season.average_efficiency) +
        (@home_team_season.adj_defensive_efficiency - @season.average_efficiency) +
        @season.average_efficiency - home_court_advantage
    end

    def home_expected_drtg
      away_expected_ortg
    end

    def away_expected_drtg
      home_expected_ortg
    end

    def expected_pace
      (@home_team_season.adj_pace - @season.average_pace) +
        (@away_team_season.adj_pace - @season.average_pace) +
        @season.average_pace
    end

    def home_expected_score
      (home_expected_ortg * expected_pace).round(2)
    end

    def away_expected_score
      (away_expected_ortg * expected_pace).round(2)
    end

    private

    # eventually this will be calculated based on team seasons but for now is a constant
    def home_court_advantage
      @neutral ? 0 : 1.5
    end
  end
end
