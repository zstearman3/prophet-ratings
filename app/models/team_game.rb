# frozen_string_literal: true

class TeamGame < ApplicationRecord
  include BasketballCalculations::Calculations

  belongs_to :game
  belongs_to :team
  belongs_to :team_season
  belongs_to :opponent_team_season, class_name: 'TeamSeason', optional: true

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
      free_throws_percentage: calculated_free_throws_percentage,
      true_shooting_percentage: calculated_true_shooting_percentage,
      effective_fg_percentage: calculated_effective_fg_percentage,
      three_pt_attempt_rate: calculated_three_pt_attempt_rate,
      free_throw_rate: calculated_free_throw_rate,
      offensive_rebound_rate: calculated_offensive_rebound_rate,
      defensive_rebound_rate: calculated_defensive_rebound_rate,
      rebound_rate: calculated_rebound_rate,
      assist_rate: calculated_assist_rate,
      steal_rate: calculated_steal_rate,
      block_rate: calculated_block_rate,
      turnover_rate: calculated_turnover_rate,
      offensive_rating: calculated_offensive_rating,
      defensive_rating: calculated_defensive_rating
    )
  end

  def points_allowed
    game.home_team_game&.id == id ? game.away_team_score : game.home_team_score
  end
end
