# frozen_string_literal: true

class StoreReviewedOffseasonInputs < ActiveRecord::Migration[8.1]
  def change
    create_table :offseason_input_revisions do |table|
      table.references :season, null: false, foreign_key: true
      table.string :kind, null: false
      table.string :version, null: false
      table.string :input_hash, null: false
      table.string :dataset_hash, null: false
      table.string :review_hash, null: false
      table.references :predecessor, foreign_key: { to_table: :offseason_input_revisions }
      table.text :reason, null: false
      table.jsonb :payload, null: false
      table.timestamps
    end
    add_index :offseason_input_revisions, %i[season_id kind input_hash], unique: true, name: 'index_offseason_revisions_identity'
    add_index :offseason_input_revisions, %i[season_id kind version], unique: true, name: 'index_offseason_revisions_version'
    add_reference :team_offseason_profiles, :recruiting_revision, foreign_key: { to_table: :offseason_input_revisions }
    add_reference :team_offseason_profiles, :departure_revision, foreign_key: { to_table: :offseason_input_revisions }
  end
end
