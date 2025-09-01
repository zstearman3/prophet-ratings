# frozen_string_literal: true

# == Schema Information
#
# Table name: team_rating_snapshots
#
#  id                        :bigint           not null, primary key
#  adj_defensive_efficiency  :decimal(6, 3)
#  adj_offensive_efficiency  :decimal(6, 3)
#  adj_pace                  :decimal(6, 3)
#  rating                    :decimal(6, 3)
#  snapshot_date             :date             not null
#  stats                     :jsonb            not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  ratings_config_version_id :bigint
#  season_id                 :bigint           not null
#  team_id                   :bigint           not null
#  team_season_id            :bigint           not null
#
# Indexes
#
#  idx_on_team_id_season_id_snapshot_date_8de7607130         (team_id,season_id,snapshot_date)
#  idx_trs_on_team_season_date_rcv_unique                    (team_id,season_id,snapshot_date,ratings_config_version_id) UNIQUE
#  index_team_rating_snapshots_on_rating_and_snapshot_date   (rating,snapshot_date)
#  index_team_rating_snapshots_on_ratings_config_version_id  (ratings_config_version_id)
#  index_team_rating_snapshots_on_season_id                  (season_id)
#  index_team_rating_snapshots_on_team_id                    (team_id)
#  index_team_rating_snapshots_on_team_season_id             (team_season_id)
#
# Foreign Keys
#
#  fk_rails_...  (ratings_config_version_id => ratings_config_versions.id)
#  fk_rails_...  (season_id => seasons.id)
#  fk_rails_...  (team_id => teams.id)
#  fk_rails_...  (team_season_id => team_seasons.id)
#
class TeamRatingSnapshot < ApplicationRecord
  belongs_to :team
  belongs_to :season
  belongs_to :team_season
  belongs_to :ratings_config_version

  validates :snapshot_date, presence: true
  validates :team_id, uniqueness: { scope: %i[season_id snapshot_date ratings_config_version] }

  store_accessor :stats, *%i[
    adj_effective_fg_percentage
    adj_effective_fg_percentage_allowed
    adj_turnover_rate
    adj_turnover_rate_forced
    adj_offensive_rebound_rate
    adj_defensive_rebound_rate
    adj_free_throw_rate
    adj_free_throw_rate_allowed
    adj_three_pt_proficiency
    adj_three_pt_proficiency_allowed
    offensive_efficiency_volatility
    defensive_efficiency_volatility
    total_volatility
    pace_volatility
    home_offense_boost
    home_defense_boost
    home_total_boost
    overall_rank
    adj_offensive_efficiency_rank
    adj_defensive_efficiency_rank
    adj_pace_rank
    adj_effective_fg_percentage_rank
    adj_turnover_rate_rank
    adj_offensive_rebound_rate_rank
    adj_free_throw_rate_rank
    adj_effective_fg_percentage_allowed_rank
    adj_turnover_rate_forced_rank
    adj_defensive_rebound_rate_rank
    adj_free_throw_rate_allowed_rank
    adj_three_pt_proficiency_rank
    adj_three_pt_proficiency_allowed_rank
  ]

  STORED_STATS = %w[
    adj_turnover_rate
    adj_turnover_rate_forced
    adj_free_throw_rate
    adj_free_throw_rate_allowed
    adj_effective_fg_percentage
    adj_effective_fg_percentage_allowed
    adj_offensive_rebound_rate
    adj_defensive_rebound_rate
    adj_three_pt_proficiency
    adj_three_pt_proficiency_allowed
    offensive_efficiency_volatility
    defensive_efficiency_volatility
    total_volatility
    pace_volatility
    home_offense_boost
    home_defense_boost
    home_total_boost
  ].freeze

  STORED_RANKS = %w[
    overall_rank
    adj_offensive_efficiency_rank
    adj_defensive_efficiency_rank
    adj_pace_rank
    adj_effective_fg_percentage_rank
    adj_turnover_rate_rank
    adj_offensive_rebound_rate_rank
    adj_free_throw_rate_rank
    adj_effective_fg_percentage_allowed_rank
    adj_turnover_rate_forced_rank
    adj_defensive_rebound_rate_rank
    adj_free_throw_rate_allowed_rank
    adj_three_pt_proficiency_rank
    adj_three_pt_proficiency_allowed_rank
  ].freeze

  STORED_STATS.each do |attr|
    define_method(attr) do
      super()&.to_f
    end
  end

  STORED_RANKS.each do |attr|
    define_method(attr) do
      super()&.to_i
    end
  end

  scope :on_date, ->(date) { where(snapshot_date: date) }
  scope :for_team, ->(team_id) { where(team_id:) }
  scope :for_season, ->(season_id) { where(season_id:) }

  def self.latest_for_season(season_id)
    where(season_id:)
      .where(snapshot_date: maximum(:snapshot_date))
  end
end
