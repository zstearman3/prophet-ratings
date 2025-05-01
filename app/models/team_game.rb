# frozen_string_literal: true

# == Schema Information
#
# Table name: team_games
#
#  id                       :bigint           not null, primary key
#  assist_rate              :decimal(6, 5)
#  assists                  :integer
#  block_rate               :decimal(6, 5)
#  blocks                   :integer
#  defensive_rating         :decimal(6, 3)
#  defensive_rebound_rate   :decimal(6, 5)
#  defensive_rebounds       :integer
#  effective_fg_percentage  :decimal(6, 5)
#  field_goals_attempted    :integer
#  field_goals_made         :integer
#  field_goals_percentage   :decimal(6, 5)
#  fouls                    :integer
#  free_throw_rate          :decimal(6, 5)
#  free_throws_attempted    :integer
#  free_throws_made         :integer
#  free_throws_percentage   :decimal(6, 5)
#  home                     :boolean          default(FALSE)
#  minutes                  :integer
#  offensive_rating         :decimal(6, 3)
#  offensive_rebound_rate   :decimal(6, 5)
#  offensive_rebounds       :integer
#  points                   :integer
#  rebound_rate             :decimal(6, 5)
#  rebounds                 :integer
#  steal_rate               :decimal(6, 5)
#  steals                   :integer
#  three_pt_attempt_rate    :decimal(6, 5)
#  three_pt_attempted       :integer
#  three_pt_made            :integer
#  three_pt_percentage      :decimal(6, 5)
#  true_shooting_percentage :decimal(6, 5)
#  turnover_rate            :decimal(6, 5)
#  turnovers                :integer
#  two_pt_attempted         :integer
#  two_pt_made              :integer
#  two_pt_percentage        :decimal(6, 5)
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  game_id                  :bigint           not null
#  opponent_team_season_id  :bigint
#  team_id                  :bigint           not null
#  team_season_id           :bigint           not null
#
# Indexes
#
#  index_team_games_on_game_id                  (game_id)
#  index_team_games_on_game_id_and_home         (game_id,home) UNIQUE
#  index_team_games_on_opponent_team_season_id  (opponent_team_season_id)
#  index_team_games_on_team_id                  (team_id)
#  index_team_games_on_team_id_and_game_id      (team_id,game_id) UNIQUE
#  index_team_games_on_team_season_id           (team_season_id)
#
# Foreign Keys
#
#  fk_rails_...  (opponent_team_season_id => team_seasons.id)
#
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
  #
  ## Alias for naming consistency in analytics
  alias_attribute :offensive_efficiency, :offensive_rating
  alias_attribute :defensive_efficiency, :defensive_rating

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
