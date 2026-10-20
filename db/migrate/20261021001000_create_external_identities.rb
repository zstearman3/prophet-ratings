# frozen_string_literal: true

class CreateExternalIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :team_external_identities do |t|
      t.references :team, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :external_id, null: false
      t.timestamps
    end
    add_index :team_external_identities, %i[provider external_id], unique: true

    create_table :game_external_identities do |t|
      t.references :game, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :external_id, null: false
      t.datetime :superseded_at
      t.timestamps
    end
    add_index :game_external_identities, %i[provider external_id], unique: true
    add_index :game_external_identities, %i[provider game_id], unique: true,
              where: 'superseded_at IS NULL', name: 'index_game_external_identities_on_active_provider_game'
  end
end
