# frozen_string_literal: true

module ProphetRatings
  class GameFinalizer
    class MissingDerivedStatsError < StandardError; end

    ##
    # Initializes a new GameFinalizer for the given game.
    # @param game The game record to be finalized.
    def initialize(game, ratings_config_version: nil)
      @game = game
      @ratings_config_version = ratings_config_version
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
    # Updates the game record with derived fields including possessions, average minutes played, and in-conference status.
    def update_derived_fields
      game.update(
        possessions: calculated_possessions,
        minutes: calculated_minutes,
        in_conference: in_conference_game?
      )
    end

    def in_conference_game?
      home_conference = game.home_team_season&.conference
      away_conference = game.away_team_season&.conference

      home_conference.present? && home_conference == away_conference
    end

    ##
    # Updates the prediction record for the game with calculated errors based on actual game results.
    # A pinned run updates its model's stored predictions; ingestion updates all stored models.
    # Actual-result errors depend on each prediction's own snapshots, never the active model.
    def finalize_prediction!
      scope = game.predictions.selected_with_legacy
      scope = scope.where(ratings_config_version: @ratings_config_version) if @ratings_config_version
      scope.includes(:home_team_snapshot, :away_team_snapshot).find_each do |prediction|
        finalize_stored_prediction(prediction)
      end
    end

    def finalize_stored_prediction(prediction)
      return unless prediction_version_valid?(prediction)

      update_prediction_errors!(prediction)
    end

    def prediction_version_valid?(prediction)
      self.class.validate_prediction_version(prediction)
      true
    rescue ArgumentError => error
      raise if @ratings_config_version

      skip_invalid_prediction(prediction, error)
    end

    def skip_invalid_prediction(prediction, error)
      Rails.logger.warn("Skipping prediction=#{prediction.id} for game=#{game.id}: #{error.message}")
      nil
    end

    public_class_method def self.validate_prediction_version(prediction)
      return if prediction.calculation_context['contract_version'] == 1

      version = prediction.ratings_config_version
      ModelConfiguration.validate_snapshots([prediction.home_team_snapshot, prediction.away_team_snapshot], version)
    end

    def update_prediction_errors!(prediction)
      error_attributes = prediction_error_attributes(prediction)
      return unless error_attributes

      prediction.update!(error_attributes)
    end

    def prediction_error_attributes(prediction)
      home_game = game.home_team_game
      away_game = game.away_team_game
      return unless home_game && away_game

      {
        home_offensive_efficiency_error: prediction.home_offensive_efficiency - home_game.offensive_efficiency,
        away_offensive_efficiency_error: prediction.away_offensive_efficiency - away_game.offensive_efficiency,
        home_defensive_efficiency_error: prediction.home_defensive_efficiency - home_game.defensive_efficiency,
        away_defensive_efficiency_error: prediction.away_defensive_efficiency - away_game.defensive_efficiency,
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
    # Calculates the average minutes played per player across both home and away team games, normalized by dividing the total minutes by 5.
    # @return [Integer, nil] The normalized average minutes per player, or nil if no data is available.
    def calculated_minutes
      arr = [game.home_team_game&.minutes, game.away_team_game&.minutes].compact
      return unless arr.any?

      arr.sum / (5 * arr.size)
    end
  end
end
