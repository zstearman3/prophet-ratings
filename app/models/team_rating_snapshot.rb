# frozen_string_literal: true

# == Schema Information
#
# Table name: team_rating_snapshots
#
#  id                       :bigint           not null, primary key
#  adj_defensive_efficiency :decimal(6, 3)
#  adj_offensive_efficiency :decimal(6, 3)
#  adj_pace                 :decimal(6, 3)
#  config_bundle_name       :string
#  rating                   :decimal(6, 3)
#  snapshot_date            :date             not null
#  stats                    :jsonb            not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  season_id                :bigint           not null
#  team_id                  :bigint           not null
#  team_season_id           :bigint           not null
#
# Indexes
#
#  idx_on_team_id_season_id_snapshot_date_8de7607130           (team_id,season_id,snapshot_date)
#  idx_on_team_id_snapshot_date_config_bundle_name_56be545c29  (team_id,snapshot_date,config_bundle_name) UNIQUE
#  index_team_rating_snapshots_on_rating_and_snapshot_date     (rating,snapshot_date)
#  index_team_rating_snapshots_on_season_id                    (season_id)
#  index_team_rating_snapshots_on_team_id                      (team_id)
#  index_team_rating_snapshots_on_team_season_id               (team_season_id)
#
# Foreign Keys
#
#  fk_rails_...  (season_id => seasons.id)
#  fk_rails_...  (team_id => teams.id)
#  fk_rails_...  (team_season_id => team_seasons.id)
#
class TeamRatingSnapshot < ApplicationRecord
  belongs_to :team
  belongs_to :season
  belongs_to :team_season

  validates :snapshot_date, presence: true
  validates :team_id, uniqueness: { scope: [:season_id, :snapshot_date] }

  store_accessor :stats, *%i[
    adj_effective_fg_percentage
    adj_effective_fg_percentage_allowed
    adj_turnover_rate
    adj_turnover_rate_forced
    adj_offensive_rebound_rate
    adj_defensive_rebound_rate
    adj_free_throw_rate
    adj_free_throw_rate_allowed
    adj_three_pt_attempt_rate
    adj_three_pt_attempt_rate_allowed
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
    adj_three_pt_attempt_rate
    adj_three_pt_attempt_rate_allowed
  ].freeze

  scope :on_date, ->(date) { where(snapshot_date: date) }
  scope :for_team, ->(team_id) { where(team_id: team_id) }
  scope :for_season, ->(season_id) { where(season_id: season_id) }

  def self.latest_for_season(season_id)
    where(season_id: season_id)
      .where(snapshot_date: maximum(:snapshot_date))
  end
end
