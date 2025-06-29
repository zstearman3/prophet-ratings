# frozen_string_literal: true

module ProphetRatings
  class GameFinalizer
    def initialize(game)
      @game = game
    end

    def call
      game.final!

      update_derived_fields
      game.home_team_game&.calculate_game_stats
      game.away_team_game&.calculate_game_stats

      finalize_prediction!
    end

    private

    attr_reader :game

    def update_derived_fields
      game.update(
        possessions: calculated_possessions,
        neutral: calculated_neutrality,
        minutes: calculated_minutes,
        in_conference: game.home_team_season&.conference == game.away_team_season&.conference
      )
    end

    def finalize_prediction!
      prediction = game.predictions.find_by(
        home_team_snapshot: game.home_team_game&.team_snapshot,
        away_team_snapshot: game.away_team_game&.team_snapshot
      )
      return unless prediction

      prediction.update!(
        home_offensive_efficiency_error: game.home_team_game.offensive_efficiency - prediction.home_offensive_efficiency,
        away_offensive_efficiency_error: game.away_team_game.offensive_efficiency - prediction.away_offensive_efficiency,
        home_defensive_efficiency_error: game.away_team_game.offensive_efficiency - prediction.away_defensive_efficiency,
        away_defensive_efficiency_error: game.home_team_game.offensive_efficiency - prediction.away_defensive_efficiency,
        pace_error: game.pace - prediction.pace
      )
    end

    def calculated_possessions
      arr = [game.home_team_game&.calculated_possessions, game.away_team_game&.calculated_possessions].compact
      return unless arr.any?

      arr.sum / arr.size
    end

    def calculated_neutrality
      return unless game.home_team&.location

      game.location.exclude?(game.home_team.location) &&
        (game.location != game.home_team.home_venue)
    end

    def calculated_minutes
      arr = [game.home_team_game&.minutes, game.away_team_game&.minutes].compact
      return unless arr.any?

      arr.sum / (5 * arr.size)
    end
  end
end
