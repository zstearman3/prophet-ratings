# frozen_string_literal: true

class TeamSeason < ApplicationRecord
  belongs_to :season
  belongs_to :team
end
