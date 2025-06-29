# frozen_string_literal: true

module ProphetRatings
  class GamePredictionBuilder
    def initialize(game, ratings_config_version: RatingsConfigVersion.current)
      @game = game
      @ratings_config_version = ratings_config_version
    end

    def call
      return unless home_snapshot && away_snapshot

      result = ProphetRatings::GamePredictor.new(
        home_rating_snapshot: home_snapshot,
        away_rating_snapshot: away_snapshot,
        neutral: game.neutral,
        season: game.season
      ).call

      Prediction.find_or_initialize_by(
        home_team_snapshot: home_snapshot,
        away_team_snapshot: away_snapshot,
        ratings_config_version:,
        game:
      ).tap do |prediction|
        prediction.home_offensive_efficiency = result[:meta][:home_expected_ortg]
        prediction.away_offensive_efficiency = result[:meta][:away_expected_ortg]
        prediction.home_defensive_efficiency = result[:meta][:away_expected_ortg]
        prediction.away_defensive_efficiency = result[:meta][:home_expected_ortg]
        prediction.home_score = result[:home_expected_score]
        prediction.away_score = result[:away_expected_score]
        prediction.home_win_probability = result[:win_probability_home]
        prediction.pace = result[:meta][:expected_pace]

        prediction.save!
      end
    end

    private

    attr_reader :game, :ratings_config_version

    def home_snapshot
      @home_snapshot ||= latest_snapshot(game.home_team_season)
    end

    def away_snapshot
      @away_snapshot ||= latest_snapshot(game.away_team_season)
    end

    def latest_snapshot(team_season)
      TeamRatingSnapshot
        .where(team_season:, ratings_config_version:)
        .where('snapshot_date <= ?', game.start_time.to_date)
        .order(snapshot_date: :desc)
        .first
    end
  end
end
