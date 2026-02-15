# frozen_string_literal: true

module ProphetRatings
  class GamePredictionBuilder
    ##
    # Initializes a new GamePredictionBuilder for the given game and ratings configuration version.
    # @param game The game for which predictions will be built.
    # @param ratings_config_version The ratings configuration version to use (defaults to the current version).
    def initialize(game, ratings_config_version: RatingsConfigVersion.current)
      @game = game
      @ratings_config_version = ratings_config_version
    end

    ##
    # Builds and saves a game prediction based on the latest team rating snapshots and ratings configuration version.
    # Returns nil if either team's rating snapshot is unavailable.
    # @return [Prediction, nil] The saved prediction record, or nil if prediction could not be generated.
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

    ##
    # Returns the latest rating snapshot for the game's home team season, or nil if none exists.
    def home_snapshot
      @home_snapshot ||= latest_snapshot(game.home_team_season)
    end

    ##
    # Returns the most recent rating snapshot for the away team's season, or nil if none exists.
    def away_snapshot
      @away_snapshot ||= latest_snapshot(game.away_team_season)
    end

    ##
    # Returns the most recent team rating snapshot for the given team season and ratings configuration version.
    # Only includes snapshots on or before the game's start date.
    #
    # @param [TeamSeason] team_season - The team season for which to retrieve the snapshot.
    # @return [TeamRatingSnapshot, nil] The latest applicable rating snapshot, or nil if none exist.
    def latest_snapshot(team_season)
      TeamRatingSnapshot
        .where(team_season:, ratings_config_version:)
        .where(snapshot_date: ..game.start_time.to_date)
        .order(snapshot_date: :desc)
        .first
    end
  end
end
