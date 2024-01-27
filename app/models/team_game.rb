# frozen_string_literal: true

class TeamGame < ApplicationRecord
  include BasketballCalculations::Calculations

  belongs_to :game
  belongs_to :team

  def calculate_game_stats
    update(
      two_pt_percentage: calculated_two_pt_percentage,
      three_pt_percentage: calculated_three_pt_percentage,
      free_throws_percentage: calculated_free_throws_percentage
    )
  end
end
