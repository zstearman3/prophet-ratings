# frozen_string_literal: true

class CreateCbbdSyncRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :cbbd_sync_runs do |t|
      t.references :season, null: false, foreign_key: true
      t.references :ratings_config_version, null: false, foreign_key: true
      t.date :season_start_date, null: false
      t.date :season_end_date, null: false
      t.date :schedule_date, null: false
      t.datetime :bucket, null: false
      t.integer :maximum_requests, null: false
      t.integer :retries, null: false
      %i[past future].each do |phase|
        t.references "#{phase}_acquisition", foreign_key: { to_table: :cbbd_review_runs }
        t.string "#{phase}_status", null: false, default: 'pending'
        t.jsonb "#{phase}_report", null: false, default: {}
      end
      t.string :analytics_status, null: false, default: 'pending'
      t.string :analytics_job_id
      t.string :analytics_error
      t.timestamps
    end
    add_index :cbbd_sync_runs, %i[season_id bucket], unique: true
  end
end
