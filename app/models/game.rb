class Game < ApplicationRecord
  validates :url, presence: true
  validates :start_time, presence: true

  belongs_to :season
  has_one :home_team_game, -> { where(home: true) }, class_name: "TeamGame", dependent: :destroy
  has_one :away_team_game, -> { where(home: false) }, class_name: "TeamGame", dependent: :destroy
  has_one :home_team, through: :home_team_game, source: :team
  has_one :away_team, through: :away_team_game, source: :team
end
