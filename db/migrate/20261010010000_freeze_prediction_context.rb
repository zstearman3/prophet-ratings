# frozen_string_literal: true

class FreezePredictionContext < ActiveRecord::Migration[8.1]
  def change
    change_table :predictions, bulk: true do |table|
      table.jsonb :calculation_context, null: false, default: {}
      table.string :forecast_kind, null: false, default: 'legacy_unverified'
      table.datetime :generated_at
      table.datetime :forecast_start_time
      table.date :input_cutoff
      table.string :revision_key
    end
    remove_index :predictions, %i[game_id home_team_snapshot_id away_team_snapshot_id], unique: true,
                                                                                        name: 'index_predictions_on_game_and_snapshots'
    add_index :predictions, %i[game_id ratings_config_version_id revision_key], unique: true, name: 'index_predictions_on_revision'
  end
end
