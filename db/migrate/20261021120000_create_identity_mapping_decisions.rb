# frozen_string_literal: true

class CreateIdentityMappingDecisions < ActiveRecord::Migration[8.1]
  def change
    create_table :identity_mapping_decisions do |t|
      t.string :request_digest, null: false
      t.string :comparison_fingerprint, null: false
      t.string :post_apply_fingerprint, null: false
      t.string :reviewer, null: false
      t.text :reason, null: false
      t.jsonb :request, null: false
      t.jsonb :result, null: false
      t.timestamps
    end
    add_index :identity_mapping_decisions, :request_digest, unique: true
  end
end
