# frozen_string_literal: true

module BasketballCalculations
  module StatFormulae
    ##
    # Calculates the two-point field goal percentage, rounded to five decimal places.
    # @return [Float, nil] The ratio of two-point shots made to attempted; nil if no attempts.
    def calculated_two_pt_percentage
      StatFormulae.ratio(two_pt_made, two_pt_attempted)&.round(5)
    end

    def calculated_three_pt_percentage
      StatFormulae.ratio(three_pt_made, three_pt_attempted)&.round(5)
    end

    def calculated_free_throws_percentage
      StatFormulae.ratio(free_throws_made, free_throws_attempted)&.round(5)
    end

    def calculated_field_goals_percentage
      StatFormulae.ratio(field_goals_made, field_goals_attempted)&.round(5)
    end

    def calculated_true_shooting_attempts
      StatFormulae.with_finite(field_goals_attempted, free_throws_attempted) do |fga, fta|
        fga.to_f + (0.44 * fta)
      end
    end

    def calculated_true_shooting_percentage
      StatFormulae.ratio(points, calculated_true_shooting_attempts&.*(2))&.round(5)
    end

    def calculated_effective_fg_percentage
      made = StatFormulae.with_finite(field_goals_made, three_pt_made) { |fgm, three_pm| fgm.to_f + (0.5 * three_pm) }
      StatFormulae.ratio(made, field_goals_attempted)&.round(5)
    end

    def calculated_three_pt_attempt_rate
      StatFormulae.ratio(three_pt_attempted, field_goals_attempted)
    end

    def calculated_free_throw_rate
      StatFormulae.ratio(free_throws_attempted, field_goals_attempted)
    end

    def calculated_three_pt_proficiency
      StatFormulae.three_point_proficiency(three_pt_made, three_pt_attempted, field_goals_attempted)&.round(5)
    end

    def legacy_three_pt_proficiency
      return nil unless StatFormulae.valid_shot_counts?(three_pt_made, three_pt_attempted, field_goals_attempted)
      return 0.0 if three_pt_attempted.zero?

      (3.0 * calculated_three_pt_attempt_rate * calculated_three_pt_percentage).round(5)
    end

    def self.three_point_proficiency(made, attempted, total_attempted)
      return nil unless valid_shot_counts?(made, attempted, total_attempted)
      return 0.0 if attempted.zero?

      ((2 * made.to_f / attempted) + (attempted.to_f / total_attempted)) / 3.0
    end

    def calculated_offensive_rebound_rate
      return nil unless opponent_game

      StatFormulae.ratio(offensive_rebounds, StatFormulae.sum(offensive_rebounds, opponent_game.defensive_rebounds))
    end

    def calculated_defensive_rebound_rate
      return nil unless opponent_game

      StatFormulae.ratio(defensive_rebounds, StatFormulae.sum(defensive_rebounds, opponent_game.offensive_rebounds))
    end

    def calculated_rebound_rate
      return nil unless opponent_game

      StatFormulae.ratio(rebounds, StatFormulae.sum(rebounds, opponent_game.rebounds))
    end

    def calculated_assist_rate
      StatFormulae.ratio(assists, field_goals_made)
    end

    def calculated_turnover_rate
      StatFormulae.ratio(turnovers, calculated_possessions)
    end

    def calculated_steal_rate
      return nil unless opponent_game

      StatFormulae.ratio(steals, opponent_game.calculated_possessions)
    end

    def calculated_block_rate
      return nil unless opponent_game

      StatFormulae.ratio(blocks, opponent_game.calculated_possessions)
    end

    def calculated_offensive_rating
      StatFormulae.ratio(points&.*(100.0), calculated_possessions)
    end

    def calculated_defensive_rating
      if opponent_game
        StatFormulae.ratio(opponent_game.points&.*(100.0), opponent_game.calculated_possessions)
      else
        StatFormulae.ratio(points_allowed&.*(100.0), calculated_possessions)
      end
    end

    def calculated_possessions
      StatFormulae.with_finite(field_goals_attempted, offensive_rebounds, turnovers, free_throws_attempted) do |fga, orb, tov, fta|
        (fga.to_f - orb.to_f + tov.to_f + (0.475 * fta.to_f)).round(1)
      end
    end

    def self.finite?(value) = value.is_a?(Numeric) && value.finite?

    def self.ratio(numerator, denominator)
      return nil unless finite?(numerator) && finite?(denominator) && !denominator.zero?

      result = numerator.to_f / denominator
      result if result.finite?
    end

    def self.sum(*values)
      values.sum if values.all? { |value| finite?(value) }
    end

    def self.with_finite(*values)
      yield(*values) if values.all? { |value| finite?(value) }
    end

    def self.valid_shot_counts?(made, attempted, total_attempted)
      [made, attempted, total_attempted].all? { |value| finite?(value) } && !total_attempted.zero?
    end
  end
end
