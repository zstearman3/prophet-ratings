# frozen_string_literal: true

module ProphetRatings
  class VolatilityCalculator
    PREDICTION_CONFIG = Rails.application.config_for(:prediction).deep_symbolize_keys
    CONFIDENCE_LEVELS = PREDICTION_CONFIG[:confidence_levels]

    def initialize(home_rating_snapshot:, away_rating_snapshot:, upset_modifier: 1.0, neutral: false, season: Season.current)
      @home_rating_snapshot = home_rating_snapshot
      @away_rating_snapshot = away_rating_snapshot
      @upset_modifier = upset_modifier
      @neutral = neutral
      @season = season
    end

    def home_offensive_volatility
      home_rating_snapshot.offensive_efficiency_volatility || season.efficiency_std_deviation
    end

    def away_offensive_volatility
      away_rating_snapshot.offensive_efficiency_volatility || season.efficiency_std_deviation
    end

    def home_defensive_volatility
      home_rating_snapshot.defensive_efficiency_volatility || season.efficiency_std_deviation
    end

    def away_defensive_volatility
      away_rating_snapshot.defensive_efficiency_volatility || season.efficiency_std_deviation
    end

    def total_home_volatility
      Math.sqrt((home_offensive_volatility**2) + (away_defensive_volatility**2)) * @upset_modifier.to_f
    end

    def total_away_volatility
      Math.sqrt((away_offensive_volatility**2) + (home_defensive_volatility**2)) * @upset_modifier.to_f
    end

    def home_pace_volatility
      home_rating_snapshot.pace_volatility || season.pace_std_deviation
    end

    def away_pace_volatility
      away_rating_snapshot.pace_volatility || season.pace_std_deviation
    end

    def total_pace_volatility
      Math.sqrt((home_pace_volatility**2) + (away_pace_volatility**2))
    end

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
