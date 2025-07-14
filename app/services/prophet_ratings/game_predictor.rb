# frozen_string_literal: true

module ProphetRatings
  DEFAULTS = Rails.application.config_for(:defaults).deep_symbolize_keys

  class GamePredictor
    def initialize(home_rating_snapshot:, away_rating_snapshot:, upset_modifier: 1.0, neutral: false, season: Season.current)
      @home_rating_snapshot = home_rating_snapshot
      @away_rating_snapshot = away_rating_snapshot
      @upset_modifier = upset_modifier
      @neutral = neutral
      @season = season
    end

    def call
      raise ArgumentError, 'Missing home or away rating snapshot' unless @home_rating_snapshot && @away_rating_snapshot

      @call ||= build_prediction_hash
    end

    private

    attr_reader :prediction_hash, :home_rating_snapshot, :away_rating_snapshot, :season

    def build_prediction_hash
      raise ArgumentError, 'Missing home or away rating snapshot' unless @home_rating_snapshot && @away_rating_snapshot

      margin = home_expected_score - away_expected_score.round(2)

      {
        home_team: home_rating_snapshot.team.school,
        away_team: away_rating_snapshot.team.school,
        favorite:,
        home_expected_score:,
        away_expected_score:,
        expected_margin: margin,
        win_probability_home:,
        confidence_level:,
        explanation: 'Based on adjusted efficiencies, expected pace, and volatility, ' \
                     "#{favorite} is favored by #{margin.abs} points.",
        meta: hash_metadata
      }
    end

    def hash_metadata
      {
        expected_pace: expected_pace.round(2),
        home_expected_ortg: home_expected_ortg.round(2),
        away_expected_ortg: away_expected_ortg.round(2),
        home_offensive_volatility: home_offensive_volatility.round(2),
        away_offensive_volatility: away_offensive_volatility.round(2),
        home_defensive_volatility: home_defensive_volatility.round(2),
        away_defensive_volatility: away_defensive_volatility.round(2)
      }
    end

    def home_expected_ortg
      return unless home_rating_snapshot && away_rating_snapshot

      @home_expected_ortg ||=
        (home_rating_snapshot.adj_offensive_efficiency - season_average_efficiency) +
        (away_rating_snapshot.adj_defensive_efficiency - season_average_efficiency) +
        home_offense_boost
    end

    def away_expected_ortg
      return unless home_rating_snapshot && away_rating_snapshot

      @away_expected_ortg ||=
        (away_rating_snapshot.adj_offensive_efficiency - season_average_efficiency) +
        (home_rating_snapshot.adj_defensive_efficiency - season_average_efficiency) +
        home_defense_boost
    end

    def home_expected_drtg
      away_expected_ortg
    end

    ##
    # Returns the expected defensive rating for the away team, defined as the home team's expected offensive rating.
    # @return [Float] The away team's expected defensive rating.
    def away_expected_drtg
      home_expected_ortg
    end

    ##
    # Calculates the expected pace for the game based on both teams' adjusted pace ratings and the season average.
    # @return [Float] The estimated number of possessions per team for the game.
    def expected_pace
      @expected_pace ||= (home_rating_snapshot.adj_pace - season.average_pace) +
                         (away_rating_snapshot.adj_pace - season.average_pace) +
                         season.average_pace
    end

    ##
    # Calculates the expected score for the home team based on its offensive rating and the predicted game pace.
    # @return [Float] The expected home team score, rounded to two decimal places.
    def home_expected_score
      @home_expected_score ||= ((home_expected_ortg * expected_pace) / 100.0).round(2)
    end

    def away_expected_score
      @away_expected_score ||= ((away_expected_ortg * expected_pace) / 100.0).round(2)
    end

    ##
    # Calculates the probability that the home team wins based on expected scores and combined volatilities.
    # @return [Float] The probability (between 0 and 1) that the home team wins, rounded to four decimal places.
    def win_probability_home
      score_diff = home_expected_score - away_expected_score
      eff_to_score_scale = (expected_pace**2) / 10_000.0

      home_score_volatility = total_home_volatility * eff_to_score_scale
      away_score_volatility = total_away_volatility * eff_to_score_scale

      volatility = Math.sqrt((home_score_volatility**2) + (away_score_volatility**2))
      probability = StatisticsUtils.normal_cdf(score_diff / volatility)

      probability.round(4)
    end

    def confidence_level
      volatility_calculator.confidence_level
    end

    def favorite
      favored_team_season = home_expected_score > away_expected_score ? home_rating_snapshot : away_rating_snapshot
      raise ArgumentError, 'Missing home or away rating snapshot' unless favored_team_season&.team&.school

      favored_team_season.team.school
    end

    def home_offense_boost
      return 0 if @neutral

      home_rating_snapshot&.home_offense_boost || default_home_boost
    end

    def home_defense_boost
      return 0 if @neutral

      home_rating_snapshot&.home_defense_boost || -default_home_boost
    end

    def default_home_boost
      @default_home_boost ||= Rails.application.config_for(:ratings).home_court_advantage
    end

    def season_average_efficiency
      season.average_efficiency || DEFAULTS[:season_defaults][:average_efficiency]
    end

    def home_offensive_volatility
      volatility_calculator.home_offensive_volatility
    end

    def away_offensive_volatility
      volatility_calculator.away_offensive_volatility
    end

    def home_defensive_volatility
      volatility_calculator.home_defensive_volatility
    end

    def away_defensive_volatility
      volatility_calculator.away_defensive_volatility
    end

    def total_home_volatility
      volatility_calculator.total_home_volatility
    end

    def total_away_volatility
      volatility_calculator.total_away_volatility
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
