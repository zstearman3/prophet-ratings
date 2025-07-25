# frozen_string_literal: true

module ProphetRatings
  class VolatilityCalculator
    PREDICTION_CONFIG = Rails.application.config_for(:prediction).deep_symbolize_keys
    CONFIDENCE_LEVELS = PREDICTION_CONFIG[:confidence_levels]

    ##
    # Initializes a new VolatilityCalculator with team rating snapshots, upset modifier, neutral flag, and season context.
    # @param home_rating_snapshot [Object] The rating snapshot for the home team.
    # @param away_rating_snapshot [Object] The rating snapshot for the away team.
    # @param upset_modifier [Float] Multiplier applied to volatility calculations to account for upset potential (default: 1.0).
    # @param neutral [Boolean] Indicates if the game is played at a neutral site (default: false).
    # @param season [Season] The season context for fallback statistics (default: current season).
    def initialize(home_rating_snapshot:, away_rating_snapshot:, upset_modifier: 1.0, neutral: false, season: Season.current)
      @home_rating_snapshot = home_rating_snapshot
      @away_rating_snapshot = away_rating_snapshot
      @upset_modifier = upset_modifier
      @neutral = neutral
      @season = season
    end

    ##
    # Returns the offensive efficiency volatility for the home team, using the rating snapshot if available or falling back to the season's efficiency standard deviation.
    # @return [Float] The home team's offensive efficiency volatility value.
    def home_offensive_volatility
      home_rating_snapshot.offensive_efficiency_volatility || season.efficiency_std_deviation
    end

    ##
    # Returns the offensive efficiency volatility for the away team, falling back to the season's efficiency standard deviation if unavailable.
    # @return [Float] The away team's offensive volatility value.
    def away_offensive_volatility
      away_rating_snapshot.offensive_efficiency_volatility || season.efficiency_std_deviation
    end

    ##
    # Returns the defensive efficiency volatility for the home team, using the rating snapshot if available or falling back to the season's efficiency standard deviation.
    # @return [Float] The home team's defensive efficiency volatility value.
    def home_defensive_volatility
      home_rating_snapshot.defensive_efficiency_volatility || season.efficiency_std_deviation
    end

    ##
    # Returns the defensive efficiency volatility for the away team, falling back to the season's efficiency standard deviation if unavailable.
    # @return [Float] The away team's defensive efficiency volatility value.
    def away_defensive_volatility
      away_rating_snapshot.defensive_efficiency_volatility || season.efficiency_std_deviation
    end

    ##
    # Calculates the combined volatility for the home team by combining home offensive and away defensive volatilities, scaled by the upset modifier.
    # @return [Float] The total home team volatility value.
    def total_home_volatility
      Math.sqrt((home_offensive_volatility**2) + (away_defensive_volatility**2)) * @upset_modifier.to_f
    end

    ##
    # Calculates the combined volatility for the away team by combining away offensive and home defensive volatilities, scaled by the upset modifier.
    # @return [Float] The total volatility value for the away team.
    def total_away_volatility
      Math.sqrt((away_offensive_volatility**2) + (home_defensive_volatility**2)) * @upset_modifier.to_f
    end

    ##
    # Returns the pace volatility for the home team, using the rating snapshot if available or falling back to the season's pace standard deviation.
    # @return [Float] The home team's pace volatility value.
    def home_pace_volatility
      home_rating_snapshot.pace_volatility || season.pace_std_deviation
    end

    ##
    # Returns the pace volatility for the away team, using the rating snapshot if available or falling back to the season's pace standard deviation.
    # @return [Float] The away team's pace volatility value.
    def away_pace_volatility
      away_rating_snapshot.pace_volatility || season.pace_std_deviation
    end

    ##
    # Calculates the combined pace volatility for both teams using the Euclidean norm.
    # @return [Float] The total pace volatility.
    def total_pace_volatility
      Math.sqrt((home_pace_volatility**2) + (away_pace_volatility**2))
    end

    ##
    # Determines the confidence level based on the absolute difference between total home and away volatilities.
    # @return [String] The confidence level: 'High', 'Medium', or 'Low'.
    def confidence_level
      volatility_gap = (total_home_volatility - total_away_volatility).abs

      if volatility_gap < CONFIDENCE_LEVELS[:high_max]
        'High'
      elsif volatility_gap < CONFIDENCE_LEVELS[:medium_max]
        'Medium'
      else
        'Low'
      end
    end

    private

    attr_reader :home_rating_snapshot, :away_rating_snapshot, :season, :upset_modifier, :neutral
  end
end
