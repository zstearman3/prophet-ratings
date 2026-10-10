# frozen_string_literal: true

class CreateGameSyncDates < ActiveRecord::Migration[8.1]
  def change
    create_table :game_sync_dates do |t|
      t.references :season, null: false, foreign_key: true
      t.date :schedule_date, null: false
      t.string :status, null: false, default: 'pending'
      t.integer :attempts, null: false, default: 0
      t.datetime :last_attempt_at
      t.datetime :completed_at
      t.integer :imported_rows
      t.text :last_error
      t.timestamps
    end
    add_index :game_sync_dates, [:season_id, :schedule_date], unique: true
  end
end
