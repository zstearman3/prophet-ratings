# frozen_string_literal: true

class CreateBetSettlements < ActiveRecord::Migration[8.1]
  def change
    create_table :bet_settlements do |t|
      t.references :game, null: false, foreign_key: { on_delete: :cascade }
      t.references :ratings_config_version, null: false, foreign_key: { on_delete: :cascade }
      t.references :prediction, foreign_key: { on_delete: :nullify }
      t.references :bet_recommendation_issue, foreign_key: { on_delete: :nullify }
      t.string :bet_type, null: false
      t.string :status, null: false
      t.text :reason
      t.integer :stake, null: false
      t.float :net_units
      t.timestamps
      t.index [:game_id, :ratings_config_version_id, :bet_type], unique: true, name: 'index_bet_settlements_on_game_model_market'
    end
  end
end
