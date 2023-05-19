class Team < ApplicationRecord
  validates :school, presence: true, uniqueness: true
  validates :url, presence: true

  has_many :team_seasons
  has_many :team_games
  has_many :home_team_games, -> { where(home: true) }, class_name: "TeamGame", dependent: :destroy
  has_many :away_team_games, -> { where(home: false) }, class_name: "TeamGame", dependent: :destroy
  has_many :games, through: :team_games
  has_many :home_games, through: :home_team_games, source: :game
  has_many :away_games, through: :away_team_games, source: :game
end
