# frozen_string_literal: true

module ProphetRatings
  class GameSimulator
    def initialize(home_rating_snapshot:, away_rating_snapshot:, upset_modifier: 1.0, neutral: false, season: Season.current)
      @home_rating_snapshot = home_rating_snapshot
      @away_rating_snapshot = away_rating_snapshot
      @upset_modifier = upset_modifier
      @neutral = neutral
      @season = season
    end

    def call
      raise ArgumentError, 'Missing home or away rating snapshot' unless @home_rating_snapshot && @away_rating_snapshot

      pace = simulate_pace
      home_ortg = simulate_home_ortg
      away_ortg = simulate_away_ortg
      {
        home_team: home_rating_snapshot.team.school,
        away_team: away_rating_snapshot.team.school,
        home_score: (pace * (home_ortg / 100.0)).round(2),
        away_score: (pace * (away_ortg / 100.0)).round(2)
      }
    end

    private

    attr_reader :home_rating_snapshot, :away_rating_snapshot, :season

    def simulate_pace
      Gaussian.new(expected_pace, total_pace_volatility).rand
    end

    def simulate_home_ortg
      Gaussian.new(home_expected_ortg, total_home_volatility).rand
    end

    def simulate_away_ortg
      Gaussian.new(away_expected_ortg, total_away_volatility).rand
    end

    def expected_pace
      @expected_pace ||= (home_rating_snapshot.adj_pace - season.average_pace) +
                         (away_rating_snapshot.adj_pace - season.average_pace) +
                         season.average_pace
    end

    def home_expected_ortg
      return unless home_rating_snapshot && away_rating_snapshot

      @home_expected_ortg ||=
        (home_rating_snapshot.adj_offensive_efficiency - season.average_efficiency) +
        (away_rating_snapshot.adj_defensive_efficiency - season.average_efficiency) +
        home_offense_boost
    end

    def away_expected_ortg
      return unless home_rating_snapshot && away_rating_snapshot

      @away_expected_ortg ||=
        (away_rating_snapshot.adj_offensive_efficiency - season.average_efficiency) +
        (home_rating_snapshot.adj_defensive_efficiency - season.average_efficiency) +
        home_defense_boost
    end

    def total_home_volatility
      volatility_calculator.total_home_volatility
    end

    def total_away_volatility
      volatility_calculator.total_away_volatility
    end

    def total_pace_volatility
      volatility_calculator.total_pace_volatility
    end

    def volatility_calculator
      @volatility_calculator ||= ProphetRatings::VolatilityCalculator.new(
        home_rating_snapshot: home_rating_snapshot,
        away_rating_snapshot: away_rating_snapshot,
        season: season,
        upset_modifier: @upset_modifier,
        neutral: @neutral
      )
    end
  end
end
