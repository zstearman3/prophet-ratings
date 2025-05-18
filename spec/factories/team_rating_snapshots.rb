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
FactoryBot.define do
  factory :team_rating_snapshot do
    team_season
    ratings_config_version
    snapshot_date { Time.zone.now }
    adj_offensive_efficiency { 100.0 }
    adj_defensive_efficiency { 100.0 }
    adj_pace { 68.0 }
    offensive_efficiency_volatility { 5.0 }
    defensive_efficiency_volatility { 5.0 }
    pace_volatility { 3.0 }
  end
end
