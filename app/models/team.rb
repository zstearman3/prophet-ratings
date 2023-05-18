class Team < ApplicationRecord
  validates :school, presence: true, uniqueness: true
  validates :url, presence: true
end
