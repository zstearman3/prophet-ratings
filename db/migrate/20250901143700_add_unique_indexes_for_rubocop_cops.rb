# frozen_string_literal: true

class AddUniqueIndexesForRubocopCops < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    # Satisfy GameOdd uniqueness validation on game_id
    add_index :game_odds, :game_id,
              unique: true,
              name: "index_game_odds_on_game_id_unique",
              algorithm: :concurrently

    # Satisfy TeamRatingSnapshot uniqueness validation on scoped columns
    add_index :team_rating_snapshots,
              %i[team_id season_id snapshot_date ratings_config_version_id],
              unique: true,
              name: "idx_trs_on_team_season_date_rcv_unique",
              algorithm: :concurrently
  end

  def down
    remove_index :game_odds, name: "index_game_odds_on_game_id_unique"
    remove_index :team_rating_snapshots, name: "idx_trs_on_team_season_date_rcv_unique"
  end
end
