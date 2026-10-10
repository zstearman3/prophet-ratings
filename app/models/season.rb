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
  RATINGS_LOCK_KEY = 'prophet-ratings:update-rankings'
  # Operator actions fail visibly when a scheduled rating writer holds the lock.
  class OperationInProgress < StandardError
  end

  validates :year, presence: true, uniqueness: true
  validate :only_one_current_season, if: :current?

  has_many :games, dependent: :destroy
  has_many :team_seasons, dependent: :destroy
  has_many :predictions, through: :games
  has_many :team_rating_snapshots, dependent: :destroy
  has_many :bet_recommendations, through: :games

  def self.current
    find_by(current: true)
  end

  def rating_team_seasons
    # Always return a fresh relation: a loaded association can omit newly prepared rows or retain stale prior provenance.
    return team_seasons.where(nil) if participation_review.blank?

    included_ids = participation_review.fetch('teams').select { |entry| entry['status'] == 'included' }.pluck('team_id')
    team_seasons.where(team_id: included_ids)
  end

  def rating_outputs?
    initialized = team_seasons.where('adj_offensive_efficiency IS NOT NULL OR adj_defensive_efficiency IS NOT NULL OR adj_pace IS NOT NULL')
    team_rating_snapshots.exists? || predictions.exists? || games.final.exists? || initialized.exists?
  end

  def update_average_ratings(as_of: nil)
    update!(
      average_efficiency: calculated_average_efficiency,
      average_pace: calculated_average_pace,
      efficiency_std_deviation: calculated_efficiency_deviation,
      pace_std_deviation: calculated_pace_deviation(as_of)
    )
  end

  # rubocop:disable-next Metrics/AbcSize
  def update_adjusted_averages
    update!(
      avg_adj_offensive_efficiency: rating_team_seasons.average(:adj_offensive_efficiency),
      avg_adj_defensive_efficiency: rating_team_seasons.average(:adj_defensive_efficiency),
      average_pace: rating_team_seasons.average(:adj_pace),
      avg_adj_effective_fg_percentage: rating_team_seasons.average(:adj_effective_fg_percentage),
      avg_adj_effective_fg_percentage_allowed: rating_team_seasons.average(:adj_effective_fg_percentage_allowed),
      avg_adj_turnover_rate: rating_team_seasons.average(:adj_turnover_rate),
      avg_adj_turnover_rate_forced: rating_team_seasons.average(:adj_turnover_rate_forced),
      avg_adj_offensive_rebound_rate: rating_team_seasons.average(:adj_offensive_rebound_rate),
      avg_adj_defensive_rebound_rate: rating_team_seasons.average(:adj_defensive_rebound_rate),
      avg_adj_free_throw_rate: rating_team_seasons.average(:adj_free_throw_rate),
      avg_adj_free_throw_rate_allowed: rating_team_seasons.average(:adj_free_throw_rate_allowed),

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

  def set_current!
    Season.with_ratings_lock do
      Season.transaction { switch_current_season! }
    end
  end

  # Share the scheduled rankings lock so setup/rebuilds cannot race live rating writes.
  def self.with_ratings_lock
    result = GoodJob::Job.advisory_lock_key(RATINGS_LOCK_KEY) { [yield] }
    raise OperationInProgress, 'Another season/rating operation is running; retry after it finishes.' unless result

    result.first
  end

  private

  def switch_current_season!
    reload
    validate_activation! unless current? && participation_review.blank?
    return if current?

    deactivate_current_season!
    update!(current: true)
  end

  def deactivate_current_season!
    Season.where(current: true).where.not(id:).find_each { |season| season.update!(current: false) }
  end

  def validate_activation!
    return SeasonParticipationReview.new(self).validate_activation if participation_review.present?

    missing_teams = Team.where.not(id: team_seasons.select(:team_id)).exists?
    incomplete = team_seasons.where(adj_offensive_efficiency: nil)
                             .or(team_seasons.where(adj_defensive_efficiency: nil)).or(team_seasons.where(adj_pace: nil))
    return if start_date < end_date && team_seasons.exists? && !missing_teams && !incomplete.exists?

    raise ArgumentError, 'Season is incomplete: prepare missing teams and initialize/review preseason ratings before activation.'
  end

  def calculated_average_pace
    rating_team_seasons.average(:pace)
  end

  def calculated_average_efficiency
    rating_team_seasons.average(:offensive_efficiency)
  end

  def calculated_efficiency_deviation
    rating_team_seasons.average(:offensive_efficiency_std_dev)
  end

  def rating_final_games
    finals = games.final
    return finals if participation_review.blank?

    ids = rating_team_seasons.select(:id)
    finals.where(id: TeamGame.where(team_season_id: ids, home: true).select(:game_id))
          .where(id: TeamGame.where(team_season_id: ids, home: false).select(:game_id))
  end

  def calculated_pace_deviation(as_of)
    results = as_of ? rating_final_games.through_schedule_date(as_of) : rating_final_games
    paces = results.filter_map(&:pace)
    return nil if paces.size < 2

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
    rating_team_seasons.pick(node)
  end

  def only_one_current_season
    return unless current? && Season.where(current: true).where.not(id:).exists?

    errors.add(:current, 'can only be set on one season at a time')
  end
end
