# frozen_string_literal: true

module ProphetRatings
  class GamePredictor
    PREDICTION_CONFIG = Rails.application.config_for(:prediction).deep_symbolize_keys
    CONFIDENCE_LEVELS = PREDICTION_CONFIG[:confidence_levels]

    def initialize(home_rating_snapshot:, away_rating_snapshot:, upset_modifier: 1.0, neutral: false, season: Season.current)
      @home_rating_snapshot = home_rating_snapshot
      @away_rating_snapshot = away_rating_snapshot
      @home_team_season = home_rating_snapshot.team_season
      @away_team_season = away_rating_snapshot.team_season
      @upset_modifier = upset_modifier
      @neutral = neutral
      @season = season
    end

    def call
      @prediction_hash ||= build_prediction_hash
    end

    def save!(game:)
      raise "Must call #call first to generate prediction" unless prediction_hash

      Prediction.create!(
        game: game,
        home_team_snapshot: home_rating_snapshot,
        away_team_snapshot: away_rating_snapshot,
        home_score: prediction_hash[:home_expected_score],
        away_score: prediction_hash[:away_expected_score],
        home_win_probability: prediction_hash[:win_probability_home],
        pace: prediction_hash[:meta][:expected_pace],
        home_offensive_efficiency: prediction_hash[:meta][:home_offensive_efficiency],
        away_offensive_efficiency: prediction_hash[:meta][:away_offensive_efficiency],
        # You can add fields like vegas spread if you want too
      )
    end

    def simulated_scores
      pace = Gaussian.new(@season.average_pace, @season.pace_std_deviation).rand
      home_ortg = Gaussian.new(home_expected_ortg, total_home_std_dev).rand
      away_ortg = Gaussian.new(away_expected_ortg, total_away_std_dev).rand
      {
        home_score: (pace * (home_ortg / 100.0)).round(2),
        away_score: (pace * (away_ortg / 100.0)).round(2)
      }
    end

    private

    attr_reader :home_team_season, :away_team_season, :prediction_hash, :home_rating_snapshot, :away_rating_snapshot

    def build_prediction_hash
      margin = (home_expected_score - away_expected_score).round(2)
    
      home_std = total_home_std_dev
      away_std = total_away_std_dev
      volatility_gap = (home_std - away_std).abs
    
      confidence_level =
        if volatility_gap < CONFIDENCE_LEVELS[:high_max]
          "High"
        elsif volatility_gap < CONFIDENCE_LEVELS[:medium_max]
          "Medium"
        else
          "Low"
        end
    
      {
        home_team: @home_team_season.team.school,
        away_team: @away_team_season.team.school,
        home_expected_score:,
        away_expected_score:,
        expected_margin: margin,
        win_probability_home:,
        confidence_level: confidence_level,
        explanation: "Based on adjusted efficiencies, expected pace, and volatility, " \
                     "#{favorite} is favored by #{margin.abs} points.",
        meta: {
          expected_pace: expected_pace.round(2),
          home_expected_ortg: home_expected_ortg.round(2),
          away_expected_ortg: away_expected_ortg.round(2),
          home_offensive_efficiency_std_dev: home_offensive_efficiency_std_dev.round(2),
          away_defensive_efficiency_std_dev: away_defensive_efficiency_std_dev.round(2),
          total_home_std_dev: home_std.round(2),
          total_away_std_dev: away_std.round(2)
        }
      }
    end

    def home_expected_ortg
      @home_expected_ortg ||= (@home_team_season.adj_offensive_efficiency - @season.average_efficiency) +
        (@away_team_season.adj_defensive_efficiency - @season.average_efficiency) +
        @season.average_efficiency + home_court_advantage
    end

    def away_expected_ortg
      @away_expected_ortg ||= (@away_team_season.adj_offensive_efficiency - @season.average_efficiency) +
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
      @home_expected_score ||= ((home_expected_ortg * expected_pace) / 100.0).round(2)
    end

    def away_expected_score
      @away_expected_score ||= ((away_expected_ortg * expected_pace) / 100.0).round(2)
    end

    def win_probability_home
      score_diff = home_expected_score - away_expected_score
      combined_std = Math.sqrt(total_home_std_dev**2 + total_away_std_dev**2)
      probability = StatisticsUtils.normal_cdf(score_diff / combined_std)
      probability.round(4)
    end    
    
    def favorite
      favored_team_season = home_expected_score > away_expected_score ? home_team_season : away_team_season
      favored_team_season.team.school
    end

    # eventually this will be calculated based on team seasons but for now is a constant
    def home_court_advantage
      @neutral ? 0 : 1.8
    end

    def home_offensive_efficiency_std_dev
      home_team_season&.offensive_efficiency_std_dev || season.efficiency_std_deviation
    end

    def away_offensive_efficiency_std_dev
      away_team_season&.offensive_efficiency_std_dev || season.efficiency_std_deviation
    end

    def home_defensive_efficiency_std_dev
      home_team_season&.defensive_efficiency_std_dev || season.efficiency_std_deviation
    end

    def away_defensive_efficiency_std_dev
      away_team_season&.defensive_efficiency_std_dev || season.efficiency_std_deviation
    end

    def total_home_std_dev
      ((home_offensive_efficiency_std_dev + away_defensive_efficiency_std_dev) / 2.0) * @upset_modifier.to_f
    end

    def total_away_std_dev
      ((away_offensive_efficiency_std_dev + home_defensive_efficiency_std_dev) / 2.0) * @upset_modifier.to_f
    end
  end
end
