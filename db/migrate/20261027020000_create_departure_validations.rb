# frozen_string_literal: true

class CreateDepartureValidations < ActiveRecord::Migration[8.1]
  def change
    validations
    proposals
    approvals
  end

  private

  def validations
    create_table :departure_validations do |table|
      table.references :departure_batch, null: false, foreign_key: true
      table.references :departure_acquisition, null: false, foreign_key: true
      table.references :departure_dataset_normalization, foreign_key: true
      table.references :offseason_input_revision, foreign_key: true
      table.string :status, null: false, default: 'queued'
      table.string :validator_version, null: false
      table.jsonb :report, null: false, default: {}
      table.jsonb :choices, null: false, default: {}
      table.string :dependency_hash
      table.jsonb :artifacts, null: false, default: {}
      table.text :publication_receipt
      table.text :certificate
      table.text :error
      table.timestamps
    end
  end

  def proposals
    create_table :departure_proposals do |table|
      table.references :departure_validation, null: false, foreign_key: true
      table.references :team, null: false, foreign_key: true
      table.jsonb :input, null: false
      table.timestamps
    end
    add_index :departure_proposals, %i[departure_validation_id team_id], unique: true
  end

  def approvals
    create_table :departure_approvals do |table|
      table.references :departure_validation, null: false, foreign_key: true, index: { unique: true }
      table.references :user, foreign_key: true
      table.references :predecessor, foreign_key: { to_table: :offseason_input_revisions }
      table.string :reviewed_by, null: false
      table.datetime :reviewed_at, null: false
      table.string :reason, null: false, default: 'Approved by admin'
      table.jsonb :document, null: false
      table.string :review_hash, null: false
      table.text :signature
      table.timestamps
    end
  end
end
