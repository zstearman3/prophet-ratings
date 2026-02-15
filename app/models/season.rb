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
#  current                                    :boolean          default(FALSE)
#  efficiency_std_deviation                   :decimal(6, 3)
#  end_date                                   :date             not null
#  name                                       :string
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
#  index_seasons_on_current  (current) UNIQUE WHERE (current IS TRUE)
#  index_seasons_on_year     (year) UNIQUE
#
class Season < ApplicationRecord
  validates :year, presence: true, uniqueness: true
  validate :only_one_current_season, if: :current?

  has_many :games, dependent: :destroy
  has_many :team_seasons, dependent: :destroy
  has_many :predictions, through: :games
  has_many :team_rating_snapshots, dependent: :destroy
  has_many :bet_recommendations, through: :games

  scope :current, -> { find_by(current: true) }

  def update_average_ratings
    update!(
      average_efficiency: calculated_average_efficiency,
      average_pace: calculated_average_pace,
      efficiency_std_deviation: calculated_efficiency_deviation,
      pace_std_deviation: calculated_pace_deviation
    )
  end

  # rubocop:disable Metrics/AbcSize
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
  # rubocop:enable Metrics/AbcSize

  def set_current!
    Season.find_each { |s| s.update!(current: false) }
    update!(current: true)
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
    paces = games.final.filter_map(&:pace)
    return nil if paces.empty?

    paces.stdev
  end

  def stddev(column)
    allowed = %i[
      adj_offensive_efficiency
      adj_defensive_efficiency
      adj_effective_fg_percentage
      adj_effective_fg_percentage_allowed
      adj_turnover_rate
      adj_turnover_rate_forced
      adj_offensive_rebound_rate
      adj_defensive_rebound_rate
      adj_free_throw_rate
      adj_free_throw_rate_allowed
    ]

    col = column.to_sym
    raise ArgumentError, "Unsupported column for stddev: #{column}" unless allowed.include?(col)

    ts = TeamSeason.arel_table
    node = Arel::Nodes::NamedFunction.new('STDDEV_POP', [ts[col]])
    team_seasons.pick(node)
  end

  def only_one_current_season
    return unless current? && Season.where(current: true).where.not(id:).exists?

    errors.add(:current, 'can only be set on one season at a time')
  end
end
