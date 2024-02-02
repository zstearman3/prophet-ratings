# frozen_string_literal: true

class Season < ApplicationRecord
  validates :year, presence: true, uniqueness: true

  has_many :games, dependent: :destroy
  has_many :team_seasons, dependent: :destroy

  def self.current
    order(year: :desc).first
  end

  def average_pace
    p = (games.sum(:possessions) / games.sum(:minutes).to_f) * 40.0
    p.to_f
  end

  def average_efficiency
    points = (games.sum(:home_team_score) + games.sum(:away_team_score)) / 2
    possessions = games.sum(:possessions)

    ((points / possessions) * 100.0).to_f
  end
end
