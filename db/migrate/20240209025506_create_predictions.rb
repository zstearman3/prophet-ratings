class CreatePredictions < ActiveRecord::Migration[7.1]
  def change
    create_table :predictions do |t|
      t.decimal "home_offensive_efficiency", precision: 6, scale: 3
      t.decimal "home_defensive_efficiency", precision: 6, scale: 3
      t.decimal "away_offensive_efficiency", precision: 6, scale: 3
      t.decimal "away_defensive_efficiency", precision: 6, scale: 3
      t.decimal "pace", precision: 6, scale: 3
      t.decimal "home_score", precision: 6, scale: 3
      t.decimal "away_score", precision: 6, scale: 3
      t.decimal "home_offensive_efficiency_error", precision: 6, scale: 3
      t.decimal "home_defensive_efficiency_error", precision: 6, scale: 3
      t.decimal "away_offensive_efficiency_error", precision: 6, scale: 3
      t.decimal "away_defensive_efficiency_error", precision: 6, scale: 3
      t.decimal "pace_error", precision: 6, scale: 3
      t.bigint "game_id", null: false
      t.index ["game_id"], name: "index_predictions_on_game_id"

      t.timestamps
    end
  end
end
