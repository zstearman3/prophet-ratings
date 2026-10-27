# frozen_string_literal: true

class CreateGameScheduleReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :game_schedule_reviews do |table|
      table.references :season, null: false, foreign_key: true
      table.references :schedule_refresh_run, null: false, foreign_key: true
      table.references :game, null: false, foreign_key: true
      table.references :source_observation, null: false, index: { unique: true }, foreign_key: { to_table: :game_observations }
      table.references :prior_observation, null: false, foreign_key: { to_table: :game_observations }
      table.references :reviewed_by, null: false, foreign_key: { to_table: :users }
      table.string :choice, null: false
      table.string :selected_external_id, null: false
      table.string :ignored_external_id, null: false
      table.string :ignored_fingerprint, null: false
      table.string :comparison_fingerprint, null: false
      table.jsonb :selected_payload, null: false
      table.jsonb :selected_schedule, null: false
      table.jsonb :participants, null: false
      table.string :reason, null: false, default: 'Approved by admin'
      table.timestamps
      table.index :ignored_external_id, unique: true
    end
  end
end
