# frozen_string_literal: true

class AddPreseasonPublications < ActiveRecord::Migration[8.1]
  def change
    add_reference :seasons, :selected_preseason_model, foreign_key: { to_table: :ratings_config_versions }
    add_column :seasons, :preseason_selection_generation, :integer, null: false, default: 0
    create_table :preseason_publications do |t|
      t.references :season, null: false, foreign_key: true
      t.references :ratings_config_version, null: false, foreign_key: true
      t.references :reviewer, null: false, foreign_key: { to_table: :users }
      t.string :mode, null: false
      t.string :status, null: false, default: 'review'
      t.string :fingerprint, null: false
      t.jsonb :report, null: false
      t.jsonb :acknowledgement, null: false, default: {}
      t.jsonb :result, null: false, default: {}
      t.text :error_message
      t.datetime :queued_at
      t.datetime :started_at
      t.datetime :published_at
      t.timestamps
    end
  end
end
