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
      @home_expected_ortg ||= (home_rating_snapshot.adj_offensive_efficiency - season.average_efficiency) +
                              (away_rating_snapshot.adj_defensive_efficiency - season.average_efficiency) +
                              season.average_efficiency + home_offense_boost
    end

    def away_expected_ortg
      @away_expected_ortg ||= (away_rating_snapshot.adj_offensive_efficiency - season.average_efficiency) +
                              (home_rating_snapshot.adj_defensive_efficiency - season.average_efficiency) +
                              season.average_efficiency + home_defense_boost
    end

    def home_expected_drtg
      away_expected_ortg
    end

    def away_expected_drtg
      home_expected_ortg
    end

    def expected_pace
      (home_rating_snapshot.adj_pace - season.average_pace) +
        (away_rating_snapshot.adj_pace - season.average_pace) +
        season.average_pace
    end

    def home_expected_score
      @home_expected_score ||= ((home_expected_ortg * expected_pace) / 100.0).round(2)
    end

    def away_expected_score
      @away_expected_score ||= ((away_expected_ortg * expected_pace) / 100.0).round(2)
    end

    def win_probability_home
      score_diff = home_expected_score - away_expected_score
      volatility = Math.sqrt((total_home_volatility**2) + (total_away_volatility**2))
      probability = StatisticsUtils.normal_cdf(score_diff / volatility)
      probability.round(4)
    end

    def favorite
      favored_team_season = home_expected_score > away_expected_score ? home_rating_snapshot : away_rating_snapshot
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
      home_rating_snapshot&.offensive_efficiency_volatility || season.efficiency_std_deviation
    end

    def away_offensive_volatility
      away_rating_snapshot&.offensive_efficiency_volatility || season.efficiency_std_deviation
    end

    def home_defensive_volatility
      home_rating_snapshot&.defensive_efficiency_volatility || season.efficiency_std_deviation
    end

    def away_defensive_volatility
      away_rating_snapshot&.defensive_efficiency_volatility || season.efficiency_std_deviation
    end

    def total_home_volatility
      ((home_offensive_volatility + away_defensive_volatility) / 2.0) * @upset_modifier.to_f
    end

    def total_away_volatility
      ((away_offensive_volatility + home_defensive_volatility) / 2.0) * @upset_modifier.to_f
    end

    def home_pace_volatility
      home_rating_snapshot&.pace_volatility || season.pace_std_deviation
    end

    def away_pace_volatility
      away_rating_snapshot&.pace_volatility || season.pace_std_deviation
    end

    def total_pace_volatility
      Math.sqrt((home_pace_volatility**2) + (away_pace_volatility**2))
    end
  end
end
