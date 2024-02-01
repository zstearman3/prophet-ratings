# frozen_string_literal: true

class TeamGame < ApplicationRecord
  include BasketballCalculations::Calculations

  belongs_to :game
  belongs_to :team
  belongs_to :team_season

  has_one :season, through: :game

  # rubocop:disable Rails/HasManyOrHasOneDependent, Rails/InverseOf
  has_one :opponent_game, lambda { |g|
                            unscope(where: :team_game_id)
                              .where(game_id: g.game_id)
                              .where.not(id: g.id)
                          }, class_name: 'TeamGame'
  # rubocop:enable Rails/HasManyOrHasOneDependent, Rails/InverseOf

  def calculate_game_stats
    update(
      two_pt_percentage: calculated_two_pt_percentage,
      three_pt_percentage: calculated_three_pt_percentage,
      free_throws_percentage: calculated_free_throws_percentage
    )
  end
end
