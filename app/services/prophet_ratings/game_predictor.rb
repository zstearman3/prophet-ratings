# frozen_string_literal: true

module ProphetRatings
  class GamePredictor
    PREDICTION_CONFIG = Rails.application.config_for(:prediction).deep_symbolize_keys
    CONFIDENCE_LEVELS = PREDICTION_CONFIG[:confidence_levels]

    def initialize(home_rating_snapshot:, away_rating_snapshot:, upset_modifier: 1.0, neutral: false, season: Season.current)
      @home_rating_snapshot = home_rating_snapshot
      @away_rating_snapshot = away_rating_snapshot
      @upset_modifier = upset_modifier
      @neutral = neutral
      @season = season
    end

    def call
      @call ||= build_prediction_hash
    end

    def simulate
      raise ArgumentError, 'Missing home or away rating snapshot' unless @home_rating_snapshot && @away_rating_snapshot

      home_team = @home_rating_snapshot.team.school
      away_team = @away_rating_snapshot.team.school
      pace = Gaussian.new(expected_pace, total_pace_volatility).rand
      home_ortg = Gaussian.new(home_expected_ortg, total_home_volatility).rand
      away_ortg = Gaussian.new(away_expected_ortg, total_away_volatility).rand
      {
        home_team:,
        away_team:,
        home_score: (pace * (home_ortg / 100.0)).round(2),
        away_score: (pace * (away_ortg / 100.0)).round(2)
      }
    end

    private

    attr_reader :prediction_hash, :home_rating_snapshot, :away_rating_snapshot, :season

    def build_prediction_hash
      margin = (home_expected_score - away_expected_score).round(2)

      home_volatility = total_home_volatility
      away_volatility = total_away_volatility
      volatility_gap = (home_volatility - away_volatility).abs

      confidence_level =
        if volatility_gap < CONFIDENCE_LEVELS[:high_max]
          'High'
        elsif volatility_gap < CONFIDENCE_LEVELS[:medium_max]
          'Medium'
        else
          'Low'
        end

      raise ArgumentError, 'Missing home or away rating snapshot' unless @home_rating_snapshot && @away_rating_snapshot

      {
        home_team: @home_rating_snapshot.team.school,
        away_team: @away_rating_snapshot.team.school,
        favorite:,
        home_expected_score:,
        away_expected_score:,
        expected_margin: margin,
        win_probability_home:,
        confidence_level:,
        explanation: 'Based on adjusted efficiencies, expected pace, and volatility, ' \
                     "#{favorite} is favored by #{margin.abs} points.",
        meta: {
          expected_pace: expected_pace.round(2),
          home_expected_ortg: home_expected_ortg.round(2),
          away_expected_ortg: away_expected_ortg.round(2),
          home_offensive_volatility: home_offensive_volatility.round(2),
          away_offensive_volatility: away_offensive_volatility.round(2),
          home_defensive_volatility: home_defensive_volatility.round(2),
          away_defensive_volatility: away_defensive_volatility.round(2)

        }
      }
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
      @expected_pace ||= ((home_rating_snapshot&.adj_pace || 0) - (season.respond_to?(:average_pace) ? season.average_pace : 0)) +
                         ((away_rating_snapshot&.adj_pace || 0) - (season.respond_to?(:average_pace) ? season.average_pace : 0)) +
                         (season.respond_to?(:average_pace) ? season.average_pace : 0)
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

    def home_offensive_volatility
      home_rating_snapshot&.offensive_efficiency_volatility ||
        (season.respond_to?(:efficiency_std_deviation) ? season.efficiency_std_deviation : 1.0)
    end

    def away_offensive_volatility
      away_rating_snapshot&.offensive_efficiency_volatility ||
        (season.respond_to?(:efficiency_std_deviation) ? season.efficiency_std_deviation : 1.0)
    end

    def home_defensive_volatility
      home_rating_snapshot&.defensive_efficiency_volatility ||
        (season.respond_to?(:efficiency_std_deviation) ? season.efficiency_std_deviation : 1.0)
    end

    ##
    # Returns the defensive efficiency volatility for the away team, using the rating snapshot if available,
    # or falling back to the season's efficiency standard deviation or 1.0.
    def away_defensive_volatility
      away_rating_snapshot&.defensive_efficiency_volatility ||
        (season.respond_to?(:efficiency_std_deviation) ? season.efficiency_std_deviation : 1.0)
    end

    ##
    # Calculates the total volatility for the home team as the root-sum-square of home offensive and away defensive volatilities,
    # scaled by the upset modifier.
    # @return [Float] The aggregated volatility value for the home team.
    def total_home_volatility
      Math.sqrt((home_offensive_volatility**2) + (away_defensive_volatility**2)) * @upset_modifier.to_f
    end

    ##
    # Calculates the total volatility for the away team by combining its offensive volatility with the home team's defensive volatility,
    # scaled by the upset modifier.
    # @return [Float] The aggregated volatility value for the away team.
    def total_away_volatility
      Math.sqrt((away_offensive_volatility**2) + (home_defensive_volatility**2)) * @upset_modifier.to_f
    end

    ##
    # Returns the home team's pace volatility, using the rating snapshot if available,
    # or falling back to the season's pace standard deviation or 1.0 if not present.
    # @return [Float] The volatility value representing the variability in the home team's pace.
    def home_pace_volatility
      home_rating_snapshot&.pace_volatility ||
        (season.respond_to?(:pace_std_deviation) ? season.pace_std_deviation : 1.0)
    end

    def away_pace_volatility
      away_rating_snapshot&.pace_volatility ||
        (season.respond_to?(:pace_std_deviation) ? season.pace_std_deviation : 1.0)
    end

    def total_pace_volatility
      Math.sqrt((home_pace_volatility**2) + (away_pace_volatility**2))
    end
  end
end
