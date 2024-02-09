# frozen_string_literal: true

class Prediction < ApplicationRecord
  belongs_to :game
  has_one :home_team_game, through: :game
  has_one :away_team_game, through: :game
  has_one :season, through: :game
end
