# frozen_string_literal: true

class Season < ApplicationRecord
  validates :year, presence: true, uniqueness: true
end
