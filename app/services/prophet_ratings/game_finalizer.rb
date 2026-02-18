# frozen_string_literal: true

module ProphetRatings
  class GameFinalizer
    class MissingDerivedStatsError < StandardError; end

    ##
    # Initializes a new GameFinalizer for the given game.
    # @param game The game record to be finalized.
    def initialize(game)
      @game = game
    end

    ##
    # Finalizes the game by updating its status, derived fields, team game statistics, and prediction errors.
    def call
      game.transaction do
        update_derived_fields
        validate_finalization_prerequisites!
        game.home_team_game&.calculate_game_stats
        game.away_team_game&.calculate_game_stats
        finalize_prediction!
        game.final!
      end
    end

    private

    attr_reader :game

    def validate_finalization_prerequisites!
      return if game.pace.present?

      missing = []
      missing << 'minutes' if game.minutes.to_i <= 0
      missing << 'possessions' if game.possessions.blank?

      raise MissingDerivedStatsError,
            "Cannot finalize game #{game.id}: missing valid #{missing.join(' and ')} required to compute pace"
    end

    ##
    # Updates the game record with derived fields including possessions, neutrality, average minutes played, and in-conference status.
    def update_derived_fields
      game.update(
        possessions: calculated_possessions,
        neutral: calculated_neutrality,
        minutes: calculated_minutes,
        in_conference: game.home_team_season&.conference == game.away_team_season&.conference
      )
    end

    ##
    # Updates the prediction record for the game with calculated errors based on actual game results.
    # If a matching prediction is found using the latest team rating snapshots, updates its offensive
    # and defensive efficiency errors and pace error by comparing predicted values to actual game statistics.
    def finalize_prediction!
      prediction = game.predictions.find_by(
        home_team_snapshot: home_snapshot,
        away_team_snapshot: away_snapshot
      )
      return unless prediction

      prediction.update!(prediction_error_attributes(prediction))
    end

    def prediction_error_attributes(prediction)
      {
        home_offensive_efficiency_error: prediction.home_offensive_efficiency - game.home_team_game.offensive_efficiency,
        away_offensive_efficiency_error: prediction.away_offensive_efficiency - game.away_team_game.offensive_efficiency,
        home_defensive_efficiency_error: prediction.home_defensive_efficiency - game.home_team_game.defensive_efficiency,
        away_defensive_efficiency_error: prediction.away_defensive_efficiency - game.away_team_game.defensive_efficiency,
        pace_error: prediction.pace - game.pace
      }
    end

    ##
    # Calculates the average possessions from the home and away team games.
    # @return [Float, nil] The average possessions if available, or nil if neither team game has possessions data.
    def calculated_possessions
      arr = [game.home_team_game&.calculated_possessions, game.away_team_game&.calculated_possessions].compact
      return unless arr.any?

      arr.sum / arr.size
    end

    ##
    # Determines if the game was played at a neutral location.
    # @return [Boolean, nil] True if the game location excludes the home team's location and is not the home team's home venue,
    # false otherwise, or nil if the home team's location is unavailable.
    def calculated_neutrality
      return unless game.home_team&.location

      game.location.exclude?(game.home_team.location) &&
        (game.location != game.home_team.home_venue)
    end

    ##
    # Calculates the average minutes played per player across both home and away team games, normalized by dividing the total minutes by 5.
    # @return [Integer, nil] The normalized average minutes per player, or nil if no data is available.
    def calculated_minutes
      arr = [game.home_team_game&.minutes, game.away_team_game&.minutes].compact
      return unless arr.any?

      arr.sum / (5 * arr.size)
    end

    ##
    # Returns the latest team rating snapshot for the home team's season as of the game start date,
    # using the current ratings configuration version.
    # @return [TeamRatingSnapshot, nil] The latest snapshot for the home team season, or nil if none exists.
    def home_snapshot
      @home_snapshot ||= latest_snapshot(game.home_team_season)
    end

    ##
    # Returns the latest team rating snapshot for the away team's season as of the game start date,
    # using the current ratings configuration version.
    # @return [TeamRatingSnapshot, nil] The latest snapshot for the away team season, or nil if none exists.
    def away_snapshot
      @away_snapshot ||= latest_snapshot(game.away_team_season)
    end

    ##
    # Returns the most recent team rating snapshot for the given team season and current ratings configuration version,
    # as of the game's start date.
    # @param [TeamSeason] team_season - The team season for which to retrieve the snapshot.
    # @return [TeamRatingSnapshot, nil] The latest applicable snapshot, or nil if none exists.
    def latest_snapshot(team_season)
      TeamRatingSnapshot
        .where(team_season:, ratings_config_version: RatingsConfigVersion.current)
        .where(snapshot_date: ..game.start_time.to_date)
        .order(snapshot_date: :desc)
        .first
    end
  end
end
