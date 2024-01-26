class CreateGames < ActiveRecord::Migration[7.1]
  def change
    create_table :games do |t|
      t.string "url", null: false
      t.datetime "start_time", null: false
      t.bigint "season_id", null: false
      t.integer "status", default: 0, null: false
      t.string "home_team_name", null: false
      t.string "away_team_name", null: false
      t.integer "home_team_score"
      t.integer "away_team_score"
      t.decimal "possessions", precision: 4, scale: 1
      t.boolean "neutral"
      t.string "location"
      t.index ["season_id"], name: "index_games_on_season_id"

      t.timestamps
    end
  end
end
