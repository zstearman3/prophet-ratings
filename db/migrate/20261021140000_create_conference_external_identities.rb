# frozen_string_literal: true

# Conference provider keys never replace local conference IDs or display aliases.
class CreateConferenceExternalIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :conference_external_identities do |table|
      table.references :conference, null: false, foreign_key: true
      table.string :provider, null: false
      table.string :external_id, null: false
      table.timestamps
    end
    add_index :conference_external_identities, %i[provider external_id], unique: true
  end
end
