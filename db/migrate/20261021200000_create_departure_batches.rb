# frozen_string_literal: true

class CreateDepartureBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :departure_batches do |table|
      table.references :season, null: false, foreign_key: true
      table.references :revision, foreign_key: { to_table: :offseason_input_revisions }
      table.references :predecessor, foreign_key: { to_table: :departure_batches }
      table.string :status, null: false, default: 'draft'
      table.jsonb :plan, null: false, default: {}
      table.jsonb :decisions, null: false, default: []
      table.jsonb :acknowledgement, null: false, default: {}
      table.string :correction_reason
      table.string :reviewed_by
      table.datetime :reviewed_at
      table.timestamps
    end

    create_table :departure_acquisitions do |table|
      table.references :departure_batch, null: false, foreign_key: true
      table.references :predecessor, foreign_key: { to_table: :departure_acquisitions }
      table.string :status, null: false, default: 'queued'
      table.jsonb :plan, null: false, default: {}
      table.jsonb :manifest, null: false, default: {}
      table.jsonb :dataset, null: false, default: {}
      table.jsonb :evidence, null: false, default: {}
      table.string :failure
      table.datetime :started_at
      table.datetime :finished_at
      table.timestamps
    end
  end
end
