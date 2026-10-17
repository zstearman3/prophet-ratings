# frozen_string_literal: true

class CreateRecruitingReviewTables < ActiveRecord::Migration[8.1]
  def change
    create_batches
    create_entries
  end

  private

  def create_batches
    create_table :recruiting_batches do |table|
      table.references :season, null: false, foreign_key: true
      table.references :revision, foreign_key: { to_table: :offseason_input_revisions }
      table.string :status, null: false, default: 'queued'
      table.integer :source_year, null: false
      table.string :source_status
      table.string :dataset_revision
      table.text :extract_bytes
      table.text :snapshot_bytes
      table.text :coverage_note
      table.text :failure_message
      table.text :next_url
      table.integer :page_count, null: false, default: 0
      table.string :reviewed_by
      table.datetime :reviewed_at
      table.timestamps
    end
  end

  def create_entries
    create_table :recruiting_entries do |table|
      table.references :recruiting_batch, null: false, foreign_key: true
      table.references :team, foreign_key: true
      table.integer :row_number, null: false
      table.string :source_label
      table.string :provider_team_id
      table.text :source_url
      table.decimal :source_rank
      table.decimal :class_points
      table.decimal :average_rating
      table.decimal :commit_count
      table.jsonb :source_row
      table.jsonb :source_errors, null: false, default: []
      table.boolean :excluded, null: false, default: false
      table.timestamps
      table.index %i[recruiting_batch_id row_number], unique: true
    end
  end
end
