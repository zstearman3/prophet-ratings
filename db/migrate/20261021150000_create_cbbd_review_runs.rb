# frozen_string_literal: true

# Private acquisition evidence and version-bound operator drafts, without domain writes.
class CreateCbbdReviewRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :cbbd_review_runs do |table|
      table.references :season, null: false, foreign_key: true
      table.date :start_date, null: false
      table.date :end_date, null: false
      table.integer :maximum_requests, null: false
      table.integer :retries, null: false
      table.string :status, null: false, default: 'queued'
      table.string :failure
      table.jsonb :manifest, null: false, default: {}
      table.jsonb :normalized_replay
      table.string :evidence_digest
      table.bigint :active_comparison_id
      table.timestamps
    end
    create_table :cbbd_review_captures do |table|
      table.references :cbbd_review_run, null: false, foreign_key: true
      table.string :capture_id, null: false
      table.binary :body, null: false
      table.jsonb :metadata, null: false
      table.timestamps
    end
    add_index :cbbd_review_captures, [:cbbd_review_run_id, :capture_id], unique: true
    create_table :cbbd_review_comparisons do |table|
      table.references :cbbd_review_run, null: false, foreign_key: true
      table.integer :version, null: false
      table.jsonb :replay, null: false
      table.jsonb :report, null: false
      table.string :artifact_digest, null: false
      table.jsonb :draft, null: false, default: {}
      table.integer :draft_revision, null: false, default: 0
      table.references :identity_mapping_decision, foreign_key: true
      table.timestamps
    end
    add_index :cbbd_review_comparisons, [:cbbd_review_run_id, :version], unique: true
    add_foreign_key :cbbd_review_runs, :cbbd_review_comparisons, column: :active_comparison_id
  end
end
