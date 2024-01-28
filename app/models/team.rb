# frozen_string_literal: true

class Team < ApplicationRecord
  validates :school, presence: true, uniqueness: true
  validates :url, presence: true

  has_many :team_seasons, dependent: :destroy
  has_many :team_games, dependent: :destroy
  has_many :home_team_games, -> { where(home: true) }, inverse_of: :team, class_name: 'TeamGame', dependent: :destroy
  has_many :away_team_games, -> { where(home: false) }, inverse_of: :team, class_name: 'TeamGame', dependent: :destroy
  has_many :games, through: :team_games
  has_many :home_games, through: :home_team_games, source: :game
  has_many :away_games, through: :away_team_games, source: :game

  scope :search, lambda { |name|
    where('school = :name OR nickname = :name OR secondary_name = :name', name:)
  }

  scope :missing_secondary_name, -> { includes(:team_games).where(team_games: { id: nil }, secondary_name: nil) }

  # Not ideal but until enough data will help determine if a game is neutral
  def probable_home_venue
    arr = home_games.order(start_time: :desc).first(30)
    arr.max_by { |i| arr.count(i) }
  end
end
