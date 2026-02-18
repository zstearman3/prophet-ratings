# frozen_string_literal: true

module ProphetRatings
  DEFAULTS = Rails.application.config_for(:defaults).deep_symbolize_keys unless const_defined?(:DEFAULTS)

  class GamePredictor
    ##
    # Initializes a new GamePredictor for a given matchup.
    # @param home_rating_snapshot [Object] The rating snapshot for the home team.
    # @param away_rating_snapshot [Object] The rating snapshot for the away team.
    # @param upset_modifier [Float] Optional modifier to adjust upset likelihood (default: 1.0).
    # @param neutral [Boolean] Whether the game is played at a neutral site (default: false).
    # @param season [Season] The season context for the prediction (default: current season).
    def initialize(home_rating_snapshot:, away_rating_snapshot:, upset_modifier: 1.0, neutral: false, season: Season.current)
      @home_rating_snapshot = home_rating_snapshot
      @away_rating_snapshot = away_rating_snapshot
      @upset_modifier = upset_modifier
      @neutral = neutral
      @season = season
    end

    ##
    # Generates and returns a prediction hash for the game based on the provided rating snapshots.
    # Raises an ArgumentError if either the home or away rating snapshot is missing.
    # @return [Hash] The prediction details including expected scores, win probability, confidence, and metadata.
    def call
      raise ArgumentError, 'Missing home or away rating snapshot' unless @home_rating_snapshot && @away_rating_snapshot

      @call ||= build_prediction_hash
    end

    private

    attr_reader :prediction_hash, :home_rating_snapshot, :away_rating_snapshot, :season

    ##
    # Builds a hash containing the predicted outcome and supporting details for a game.
    # Raises an ArgumentError if either rating snapshot is missing.
    # @return [Hash] A hash with predicted scores, favorite, win probability, confidence level, explanation, and metadata.
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

    ##
    # Returns a hash containing rounded metadata values for expected pace, offensive ratings, and offensive and defensive volatilities for both home and away teams.
    # @return [Hash] The metadata hash with keys for expected pace, offensive ratings, and volatilities.
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

    ##
    # Calculates the expected offensive rating for the home team, adjusted for opponent defense, season average efficiency, and home court advantage.
    # @return [Float, nil] The adjusted expected offensive rating for the home team, or nil if rating snapshots are missing.
    def home_expected_ortg
      return unless home_rating_snapshot && away_rating_snapshot

      @home_expected_ortg ||=
        home_rating_snapshot.adj_offensive_efficiency +
        away_rating_snapshot.adj_defensive_efficiency -
        season_average_efficiency +
        home_offense_boost
    end

    ##
    # Calculates the away team's expected offensive rating for the game.
    # Combines the away team's adjusted offensive efficiency, the home team's adjusted defensive efficiency, and any applicable home defense boost, all relative to the season average efficiency.
    # @return [Float, nil] The expected offensive rating for the away team, or nil if rating snapshots are missing.
    def away_expected_ortg
      return unless home_rating_snapshot && away_rating_snapshot

      @away_expected_ortg ||=
        away_rating_snapshot.adj_offensive_efficiency +
        home_rating_snapshot.adj_defensive_efficiency -
        season_average_efficiency +
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
    ##
    # Calculates the expected pace of the game as the average adjusted pace of both teams relative to the season average.
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
    ##
    # Calculates the probability that the home team wins based on expected scores and combined team volatilities.
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

    ##
    # Returns the confidence level of the prediction based on volatility calculations.
    # @return [String] The confidence level label as determined by the volatility calculator.
    def confidence_level
      volatility_calculator.confidence_level
    end

    ##
    # Returns the school name of the team predicted to win based on expected scores.
    # @return [String] The favored team's school name.
    # @raise [ArgumentError] If the favored team's school cannot be determined.
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

    ##
    # Retrieves the default home court advantage value from the ratings configuration.
    # @return [Numeric] The configured home court advantage value.
    def default_home_boost
      @default_home_boost ||= Rails.application.config_for(:ratings).home_court_advantage
    end

    ##
    # Returns the season's average efficiency, falling back to a default value if unavailable.
    # @return [Float] The average efficiency for the season.
    def season_average_efficiency
      season.average_efficiency || DEFAULTS[:season_defaults][:average_efficiency]
    end

    ##
    # Returns the home team's offensive volatility for the predicted game.
    def home_offensive_volatility
      volatility_calculator.home_offensive_volatility
    end

    ##
    # Returns the offensive volatility value for the away team as calculated by the volatility calculator.
    # @return [Float] The away team's offensive volatility.
    def away_offensive_volatility
      volatility_calculator.away_offensive_volatility
    end

    ##
    # Returns the home team's defensive volatility for the predicted game.
    def home_defensive_volatility
      volatility_calculator.home_defensive_volatility
    end

    ##
    # Returns the away team's defensive volatility for the predicted game.
    def away_defensive_volatility
      volatility_calculator.away_defensive_volatility
    end

    ##
    # Returns the total volatility for the home team as calculated by the volatility calculator.
    # @return [Float] The total home team volatility value.
    def total_home_volatility
      volatility_calculator.total_home_volatility
    end

    ##
    # Returns the total volatility for the away team as calculated by the volatility calculator.
    # @return [Float] The away team's total volatility value.
    def total_away_volatility
      volatility_calculator.total_away_volatility
    end

    ##
    # Lazily initializes and returns a VolatilityCalculator for the current game prediction context.
    # @return [ProphetRatings::VolatilityCalculator] The volatility calculator instance for this prediction.
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
