# frozen_string_literal: true

class AddUniqueIndexToPredictionsOnGameAndSnapshots < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_index :predictions,
              %i[game_id home_team_snapshot_id away_team_snapshot_id],
              unique: true,
              name: "index_predictions_on_game_and_snapshots",
              algorithm: :concurrently
  end

  def down
    remove_index :predictions,
                 name: "index_predictions_on_game_and_snapshots",
                 algorithm: :concurrently
  end
end
