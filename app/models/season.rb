# frozen_string_literal: true

# == Schema Information
#
# Table name: seasons
#
#  id                                         :bigint           not null, primary key
#  average_efficiency                         :decimal(6, 3)
#  average_pace                               :decimal(6, 3)
#  avg_adj_defensive_efficiency               :decimal(6, 3)
#  avg_adj_defensive_rebound_rate             :decimal(6, 5)
#  avg_adj_effective_fg_percentage            :decimal(6, 5)
#  avg_adj_effective_fg_percentage_allowed    :decimal(6, 5)
#  avg_adj_free_throw_rate                    :decimal(6, 5)
#  avg_adj_free_throw_rate_allowed            :decimal(6, 5)
#  avg_adj_offensive_efficiency               :decimal(6, 3)
#  avg_adj_offensive_rebound_rate             :decimal(6, 5)
#  avg_adj_three_pt_proficiency               :decimal(6, 5)
#  avg_adj_turnover_rate                      :decimal(6, 5)
#  avg_adj_turnover_rate_forced               :decimal(6, 5)
#  efficiency_std_deviation                   :decimal(6, 3)
#  end_date                                   :date             not null
#  pace_std_deviation                         :decimal(6, 3)
#  start_date                                 :date             not null
#  stddev_adj_defensive_efficiency            :decimal(6, 3)
#  stddev_adj_defensive_rebound_rate          :decimal(6, 5)
#  stddev_adj_effective_fg_percentage         :decimal(6, 5)
#  stddev_adj_effective_fg_percentage_allowed :decimal(6, 5)
#  stddev_adj_free_throw_rate                 :decimal(6, 5)
#  stddev_adj_free_throw_rate_allowed         :decimal(6, 5)
#  stddev_adj_offensive_efficiency            :decimal(6, 3)
#  stddev_adj_offensive_rebound_rate          :decimal(6, 5)
#  stddev_adj_three_pt_proficiency            :decimal(6, 5)
#  stddev_adj_turnover_rate                   :decimal(6, 5)
#  stddev_adj_turnover_rate_forced            :decimal(6, 5)
#  year                                       :integer          not null
#  created_at                                 :datetime         not null
#  updated_at                                 :datetime         not null
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

  def update_adjusted_averages
    update!(
      avg_adj_offensive_efficiency: team_seasons.average(:adj_offensive_efficiency),
      avg_adj_defensive_efficiency: team_seasons.average(:adj_defensive_efficiency),
      average_pace: team_seasons.average(:adj_pace),
      avg_adj_effective_fg_percentage: team_seasons.average(:adj_effective_fg_percentage),
      avg_adj_effective_fg_percentage_allowed: team_seasons.average(:adj_effective_fg_percentage_allowed),
      avg_adj_turnover_rate: team_seasons.average(:adj_turnover_rate),
      avg_adj_turnover_rate_forced: team_seasons.average(:adj_turnover_rate_forced),
      avg_adj_offensive_rebound_rate: team_seasons.average(:adj_offensive_rebound_rate),
      avg_adj_defensive_rebound_rate: team_seasons.average(:adj_defensive_rebound_rate),
      avg_adj_free_throw_rate: team_seasons.average(:adj_free_throw_rate),
      avg_adj_free_throw_rate_allowed: team_seasons.average(:adj_free_throw_rate_allowed),
  
      stddev_adj_offensive_efficiency: stddev(:adj_offensive_efficiency),
      stddev_adj_defensive_efficiency: stddev(:adj_defensive_efficiency),
      stddev_adj_effective_fg_percentage: stddev(:adj_effective_fg_percentage),
      stddev_adj_effective_fg_percentage_allowed: stddev(:adj_effective_fg_percentage_allowed),
      stddev_adj_turnover_rate: stddev(:adj_turnover_rate),
      stddev_adj_turnover_rate_forced: stddev(:adj_turnover_rate_forced),
      stddev_adj_offensive_rebound_rate: stddev(:adj_offensive_rebound_rate),
      stddev_adj_defensive_rebound_rate: stddev(:adj_defensive_rebound_rate),
      stddev_adj_free_throw_rate: stddev(:adj_free_throw_rate),
      stddev_adj_free_throw_rate_allowed: stddev(:adj_free_throw_rate_allowed)
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

  def stddev(column)
    team_seasons.pick(Arel.sql("STDDEV_POP(#{column})"))
  end
end
