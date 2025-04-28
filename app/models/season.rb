# frozen_string_literal: true

# == Schema Information
#
# Table name: seasons
#
#  id                       :bigint           not null, primary key
#  average_efficiency       :decimal(6, 3)
#  average_pace             :decimal(6, 3)
#  efficiency_std_deviation :decimal(6, 3)
#  end_date                 :date             not null
#  pace_std_deviation       :decimal(6, 3)
#  start_date               :date             not null
#  year                     :integer          not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Indexes
#
#  index_seasons_on_year  (year) UNIQUE
#
class Season < ApplicationRecord
  validates :year, presence: true, uniqueness: true

  has_many :games, dependent: :destroy
  has_many :team_seasons, dependent: :destroy
  has_many :predictions, through: :games

  def self.current
    order(year: :desc).first
  end

  def update_average_ratings
    update!(
      average_efficiency: calculated_average_efficiency,
      average_pace: calculated_average_pace,
      efficiency_std_deviation: calculated_efficiency_deviation,
      pace_std_deviation: calculated_pace_deviation
    )
  end

  private

  def calculated_average_pace
    team_seasons.average(:pace)
  end

  def calculated_average_efficiency
    team_seasons.average(:offensive_efficiency)
  end

  def calculated_efficiency_deviation
    team_seasons.average(:offensive_efficiency_std_dev)
  end

  def calculated_pace_deviation
    games.map(&:pace).stdev
  end
end
