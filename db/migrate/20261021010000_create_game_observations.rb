# frozen_string_literal: true

class CreateGameObservations < ActiveRecord::Migration[8.1]
  def change
    create_table :game_observations do |table|
      table.references :game, foreign_key: true
      table.string :provider
      table.string :external_game_id
      table.string :semantic_profile
      table.string :outcome, null: false
      table.text :reason
      table.boolean :accepted, null: false, default: false
      table.jsonb :normalized_payload, null: false, default: {}
      table.jsonb :raw_payload, null: false, default: {}
      table.string :payload_digest
      table.datetime :captured_at
      table.datetime :source_updated_at
      table.timestamps
    end
    add_index :game_observations, %i[game_id accepted id]
    add_index :game_observations, %i[provider external_game_id]
  end
end
