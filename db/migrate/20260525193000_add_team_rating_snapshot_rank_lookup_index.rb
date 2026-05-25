# frozen_string_literal: true

class AddTeamRatingSnapshotRankLookupIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :team_rating_snapshots,
              %i[team_season_id ratings_config_version_id snapshot_date],
              name: 'index_team_rating_snapshots_on_team_season_config_date',
              algorithm: :concurrently
  end
end
