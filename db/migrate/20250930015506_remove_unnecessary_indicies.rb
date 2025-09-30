class RemoveUnnecessaryIndicies < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    remove_index :team_rating_snapshots,
                  name: :idx_on_team_id_season_id_snapshot_date_8de7607130,
                  algorithm: :concurrently
    remove_index :game_odds, name: :index_game_odds_on_game_id, algorithm: :concurrently
  end

  def down
    add_index :team_rating_snapshots,
              %i[team_id season_id snapshot_date],
              name: :idx_on_team_id_season_id_snapshot_date_8de7607130,
              algorithm: :concurrently
    add_index :game_odds, :game_id, name: :index_game_odds_on_game_id, algorithm: :concurrently
  end
end
