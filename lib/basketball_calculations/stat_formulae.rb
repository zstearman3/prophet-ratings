# frozen_string_literal: true

module BasketballCalculations
  module StatFormulae
    ##
    # Calculates the two-point field goal percentage, rounded to five decimal places.
    # @return [Float, nil] The ratio of two-point shots made to attempted; nil if no attempts.
    def calculated_two_pt_percentage
      return nil if two_pt_attempted.to_i.zero?

      (two_pt_made.to_f / two_pt_attempted).round(5)
    end

    def calculated_three_pt_percentage
      return nil if three_pt_attempted.to_i.zero?

      (three_pt_made.to_f / three_pt_attempted).round(5)
    end

    def calculated_free_throws_percentage
      return nil if free_throws_attempted.to_i.zero?

      (free_throws_made.to_f / free_throws_attempted).round(5)
    end

    def calculated_field_goals_percentage
      (field_goals_made.to_f / field_goals_attempted).round(5)
    end

    def calculated_true_shooting_attempts
      field_goals_attempted.to_f + (0.44 * free_throws_attempted)
    end

    def calculated_true_shooting_percentage
      (points.to_f / (2 * calculated_true_shooting_attempts)).round(5)
    end

    def calculated_effective_fg_percentage
      ((field_goals_made.to_f + (0.5 * three_pt_made)) / field_goals_attempted).round(5)
    end

    def calculated_three_pt_attempt_rate
      (three_pt_attempted.to_f / field_goals_attempted).to_f
    end

    def calculated_free_throw_rate
      (free_throws_attempted.to_f / field_goals_attempted).to_f
    end

    def calculated_three_pt_proficiency
      StatFormulae.three_point_proficiency(three_pt_made, three_pt_attempted, field_goals_attempted)&.round(5)
    end

    def legacy_three_pt_proficiency
      percentage = calculated_three_pt_percentage
      return 0.0 unless percentage

      (3.0 * calculated_three_pt_attempt_rate * percentage).round(5)
    end

    def self.three_point_proficiency(made, attempted, total_attempted)
      return nil if total_attempted.to_i.zero?
      return 0.0 if attempted.to_i.zero?

      ((2 * made.to_f / attempted) + (attempted.to_f / total_attempted)) / 3.0
    end

    def calculated_offensive_rebound_rate
      return nil unless opponent_game

      (offensive_rebounds.to_f / (offensive_rebounds + opponent_game.defensive_rebounds)).to_f
    end

    def calculated_defensive_rebound_rate
      return nil unless opponent_game

      (defensive_rebounds.to_f / (defensive_rebounds + opponent_game.offensive_rebounds)).to_f
    end

    def calculated_rebound_rate
      return nil unless opponent_game

      (rebounds.to_f / (rebounds + opponent_game.rebounds)).to_f
    end

    def calculated_assist_rate
      (assists.to_f / field_goals_made).to_f
    end

    def calculated_turnover_rate
      (turnovers.to_f / calculated_possessions).to_f
    end

    def calculated_steal_rate
      return nil unless opponent_game

      (steals.to_f / opponent_game.calculated_possessions).to_f
    end

    def calculated_block_rate
      return nil unless opponent_game

      (blocks.to_f / opponent_game.calculated_possessions).to_f
    end

    def calculated_offensive_rating
      (100.0 * points.to_f / calculated_possessions).to_f
    end

    def calculated_defensive_rating
      if opponent_game
        (100.0 * opponent_game.points.to_f / opponent_game.calculated_possessions).to_f
      else
        (100.0 * points_allowed.to_f / calculated_possessions).to_f
      end
    end

    def calculated_possessions
      (field_goals_attempted.to_f - offensive_rebounds.to_f + turnovers.to_f +
      (0.475 * free_throws_attempted.to_f)).round(1)
    end
  end
end
