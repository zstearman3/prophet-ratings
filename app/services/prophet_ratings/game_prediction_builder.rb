# frozen_string_literal: true

module ProphetRatings
  class GamePredictionBuilder
    ##
    # Initializes a new GamePredictionBuilder for the given game and ratings configuration version.
    # @param game The game for which predictions will be built.
    # @param ratings_config_version The ratings configuration version to use (defaults to the configured bundle).
    def initialize(game, ratings_config_version: nil)
      @game = game
      @ratings_config_version = RatingsConfigVersion.resolve(ratings_config_version)
      @config = @ratings_config_version.settings
    end

    ##
    # Builds and saves a game prediction based on the latest team rating snapshots and ratings configuration version.
    # Returns nil and logs a warning if required prediction inputs are unavailable.
    # @return [Prediction, nil] The saved prediction record, or nil if prediction could not be generated.
    def call
      return unless prediction_inputs_available?

      result = ProphetRatings::GamePredictor.new(
        home_rating_snapshot: home_snapshot,
        away_rating_snapshot: away_snapshot,
        venue: { type: game.venue_type, confidence: game.venue_confidence },
        season: game.season,
        ratings_config_version:
      ).call

      Prediction.find_or_initialize_by(
        home_team_snapshot: home_snapshot,
        away_team_snapshot: away_snapshot,
        ratings_config_version:,
        game:
      ).tap do |prediction|
        prediction.assign_attributes(prediction_attributes(result))

        prediction.save!
      end
    end

    private

    attr_reader :game, :ratings_config_version

    def prediction_inputs_available?
      values = prediction_input_values + required_snapshot_volatilities
      return true if values.all? { |value| value.is_a?(Numeric) && value.finite? && value >= 0 } &&
                     game.season.average_pace&.positive? && expected_pace.positive?

      Rails.logger.warn("Prediction skipped for game=#{game.id}: missing or invalid rating inputs")
      false
    end

    # Shared-pace persisted diagnostics require snapshot SDs, not mutable fallbacks.
    def required_snapshot_volatilities
      return [] unless @config.dig(:prediction, :uncertainty_model) == 'shared_pace_v1'
      return [nil] unless home_snapshot && away_snapshot

      [home_snapshot, away_snapshot].flat_map do |snapshot|
        [snapshot.offensive_efficiency_volatility, snapshot.defensive_efficiency_volatility, snapshot.pace_volatility]
      end
    end

    def expected_pace
      home_snapshot.adj_pace + away_snapshot.adj_pace - game.season.average_pace
    end

    def prediction_input_values
      return [nil] unless home_snapshot && away_snapshot

      season = game.season
      deviation = season.efficiency_std_deviation || @config.dig(:baseline_volatility, :efficiency_volatility)
      [season.average_pace] + [home_snapshot, away_snapshot].flat_map do |snapshot|
        [snapshot.adj_offensive_efficiency, snapshot.adj_defensive_efficiency, snapshot.adj_pace,
         snapshot.offensive_efficiency_volatility || deviation, snapshot.defensive_efficiency_volatility || deviation,
         snapshot.pace_volatility || season.pace_std_deviation || @config.dig(:baseline_volatility, :pace_volatility)]
      end
    end

    def prediction_attributes(result)
      {
        home_offensive_efficiency: result[:meta][:home_expected_ortg],
        away_offensive_efficiency: result[:meta][:away_expected_ortg],
        home_defensive_efficiency: result[:meta][:away_expected_ortg],
        away_defensive_efficiency: result[:meta][:home_expected_ortg],
        home_score: result[:home_expected_score],
        away_score: result[:away_expected_score],
        home_win_probability: result[:win_probability_home],
        pace: result[:meta][:expected_pace]
      }
    end

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
    # Only includes snapshots on or before the game's Eastern schedule date.
    #
    # @param [TeamSeason] team_season - The team season for which to retrieve the snapshot.
    # @return [TeamRatingSnapshot, nil] The latest applicable rating snapshot, or nil if none exist.
    def latest_snapshot(team_season)
      TeamRatingSnapshot
        .where(team_season:, ratings_config_version:)
        .where(snapshot_date: ..game.schedule_date)
        .order(snapshot_date: :desc)
        .first
    end
  end
end
