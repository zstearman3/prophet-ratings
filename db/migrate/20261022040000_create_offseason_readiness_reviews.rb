# frozen_string_literal: true

class CreateOffseasonReadinessReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :offseason_readiness_reviews do |t|
      t.references :season, null: false, foreign_key: true
      t.references :ratings_config_version, foreign_key: true
      t.references :reviewer, null: false, foreign_key: { to_table: :users }
      t.string :fingerprint, null: false
      t.jsonb :report, null: false
      t.jsonb :acknowledgement, null: false, default: {}
      t.jsonb :deferrals, null: false, default: {}
      t.jsonb :results, null: false, default: {}
      t.jsonb :attempts, null: false, default: []
      t.timestamps
    end
  end
end
