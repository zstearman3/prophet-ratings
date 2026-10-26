# frozen_string_literal: true

# Additive storage: legacy acquisition and revision JSON is intentionally untouched.
class AddDepartureCaptureStorage < ActiveRecord::Migration[8.1]
  def change
    create_table :departure_source_captures do |table|
      table.string :sha256, null: false
      table.bigint :byte_size, null: false
      table.binary :body, null: false
    end
    add_index :departure_source_captures, :sha256, unique: true

    create_table :departure_capture_observations do |table|
      table.references :departure_source_capture, null: false, foreign_key: true, index: { name: 'idx_departure_observation_capture' }
      table.references :departure_acquisition, null: false, foreign_key: true, index: { name: 'idx_departure_observation_origin' }
      table.string :source_id, null: false
      table.jsonb :metadata, null: false
      table.string :extraction_version, null: false
    end
    add_index :departure_capture_observations, %i[departure_acquisition_id source_id], unique: true,
                                                                                       name: 'idx_departure_observation_identity'

    create_table :departure_source_normalizations do |table|
      table.references :departure_source_capture, null: false, foreign_key: true, index: { name: 'idx_departure_normalization_capture' }
      table.string :identity, null: false
      table.jsonb :contract, null: false
      table.string :status, null: false, default: 'running'
      table.string :rows_digest
      table.integer :row_count, null: false, default: 0
      table.text :failure
    end
    add_index :departure_source_normalizations, :identity, unique: true

    create_table :departure_normalized_rows do |table|
      table.references :departure_source_normalization, null: false, foreign_key: true, index: { name: 'idx_departure_row_source' }
      table.integer :ordinal, null: false
      table.string :row_key, null: false
      table.bigint :provider_team_id
      table.bigint :provider_player_id
      table.json :fact, null: false
    end
    add_index :departure_normalized_rows, %i[departure_source_normalization_id ordinal], unique: true, name: 'idx_departure_row_order'
    add_index :departure_normalized_rows, %i[departure_source_normalization_id row_key], unique: true, name: 'idx_departure_row_identity'

    create_table :departure_dataset_normalizations do |table|
      table.string :identity, null: false
      table.string :status, null: false, default: 'running'
      table.jsonb :header, null: false
      table.jsonb :source_normalization_ids, null: false, default: {}
      table.string :dataset_revision
      table.jsonb :summary, null: false, default: {}
    end
    add_index :departure_dataset_normalizations, :identity, unique: true

    create_table :departure_dataset_rows do |table|
      table.references :departure_dataset_normalization, null: false, foreign_key: true, index: { name: 'idx_departure_dataset_row_parent' }
      table.string :kind, null: false
      table.integer :ordinal, null: false
      table.json :fact, null: false
    end
    add_index :departure_dataset_rows, %i[departure_dataset_normalization_id kind ordinal], unique: true,
                                                                                            name: 'idx_departure_dataset_row_order'
  end
end
