# frozen_string_literal: true

class CreateOffseasonReadinessOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :offseason_readiness_operations do |t|
      t.references :season, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.references :offseason_readiness_review, foreign_key: true, index: { name: 'index_readiness_operations_on_review_id' }
      t.string :action, null: false
      t.string :status, null: false, default: 'queued'
      t.jsonb :inputs, null: false, default: {}
      t.jsonb :report, null: false, default: {}
      t.text :error_message
      t.timestamps
    end
  end
end
