# frozen_string_literal: true

class TeamSeason < ApplicationRecord
  belongs_to :season
  belongs_to :team

  has_many :team_games, dependent: :destroy
  has_many :games, through: :team_games
end
