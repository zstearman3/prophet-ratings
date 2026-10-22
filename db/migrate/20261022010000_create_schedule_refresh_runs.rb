# frozen_string_literal: true

class CreateScheduleRefreshRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :schedule_refresh_runs do |table|
      table.references :season, null: false, foreign_key: true
      table.references :requested_by, null: false, foreign_key: { to_table: :users }
      table.references :retry_of, foreign_key: { to_table: :schedule_refresh_runs }
      table.string :provider, null: false
      table.date :start_date, null: false
      table.date :end_date, null: false
      table.jsonb :requested_dates, null: false, default: []
      table.integer :max_requests
      table.integer :retries
      table.string :status, null: false, default: 'queued'
      table.jsonb :report, null: false, default: {}
      table.text :error
      table.datetime :started_at
      table.datetime :finished_at
      table.timestamps
    end
    create_table :schedule_deferrals do |table|
      table.references :season, null: false, foreign_key: true
      table.references :requested_by, null: false, foreign_key: { to_table: :users }
      table.text :reason, null: false
      table.timestamps
    end
  end
end
