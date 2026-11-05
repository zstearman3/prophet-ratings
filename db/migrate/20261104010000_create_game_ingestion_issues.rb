# frozen_string_literal: true

class CreateGameIngestionIssues < ActiveRecord::Migration[8.1]
  def change
    create_table :game_ingestion_issues do |t|
      t.references :season, null: false, foreign_key: true
      t.references :game, foreign_key: true
      t.string :provider, null: false
      t.string :external_game_id, null: false
      t.string :category, null: false
      t.string :state, null: false, default: 'open'
      t.references :original_observation, null: false, foreign_key: { to_table: :game_observations }
      t.references :latest_observation, null: false, foreign_key: { to_table: :game_observations }
      t.string :source_fingerprint, null: false
      t.jsonb :effective_payload, null: false, default: {}
      t.jsonb :participants, null: false, default: {}
      t.references :retry_acquisition, foreign_key: { to_table: :cbbd_review_runs }
      t.string :retry_job_id
      t.string :retry_status
      t.timestamps
      t.index [:season_id, :provider, :external_game_id, :category], unique: true, name: 'index_ingestion_issues_on_source_category'
      t.index [:state, :season_id, :id]
    end
    create_table :game_ingestion_decisions do |t|
      t.references :game_ingestion_issue, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.string :source_fingerprint, null: false
      t.string :comparison_fingerprint, null: false
      t.jsonb :values, null: false, default: {}
      t.string :message, null: false
      t.timestamps
    end
  end
end
