# frozen_string_literal: true

class Game < ApplicationRecord
  validates :url, presence: true
  validates :start_time, presence: true

  belongs_to :season
  has_one :home_team_game, -> { where(home: true) }, inverse_of: :game, class_name: 'TeamGame', dependent: :destroy
  has_one :away_team_game, -> { where(home: false) }, inverse_of: :game, class_name: 'TeamGame', dependent: :destroy
  has_one :home_team, through: :home_team_game, source: :team
  has_one :away_team, through: :away_team_game, source: :team

  enum status: { scheduled: 0, final: 1, canceled: 2 }

  def finalize
    final!

    calculate_possessions
    calculate_neutrality

    home_team_game&.calculate_game_stats
    away_team_game&.calculate_game_stats
  end

  private

  def calculated_possessions
    arr = [home_team_game&.calculated_possessions, away_team_game&.calculated_possessions].compact

    return unless arr.size.positive?

    (arr.sum / arr.size)
  end
end
