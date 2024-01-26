# frozen_string_literal: true

module BasketballCalculations
  module Calculations
    def calculated_two_pt_percentage
      (two_pt_made.to_f / two_pt_attempted).round(5)
    end

    def calculated_three_pt_percentage
      (three_pt_made.to_f / three_pt_attempted).round(5)
    end

    def calculated_free_throws_percentage
      (free_throws_made.to_f / free_throws_attempted).round(5)
    end

    def calculated_possessions
      (field_goals_attempted.to_f - offensive_rebounds.to_f + turnovers.to_f +
      (0.475 * free_throws_attempted.to_f)).round(1)
    end
  end
end
