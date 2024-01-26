class CreateTeamGames < ActiveRecord::Migration[7.1]
  def change
    create_table :team_games do |t|
      t.bigint "team_id", null: false
      t.bigint "game_id", null: false
      t.boolean "home", default: false
      t.integer "minutes"
      t.integer "field_goals_made"
      t.integer "field_goals_attempted"
      t.decimal "field_goals_percentage", precision: 6, scale: 5
      t.integer "two_pt_made"
      t.integer "two_pt_attempted"
      t.decimal "two_pt_percentage", precision: 6, scale: 5
      t.integer "three_pt_made"
      t.integer "three_pt_attempted"
      t.decimal "three_pt_percentage", precision: 6, scale: 5
      t.integer "free_throws_made"
      t.integer "free_throws_attempted"
      t.decimal "free_throws_percentage", precision: 6, scale: 5
      t.integer "offensive_rebounds"
      t.integer "defensive_rebounds"
      t.integer "rebounds"
      t.integer "assists"
      t.integer "steals"
      t.integer "blocks"
      t.integer "turnovers"
      t.integer "fouls"
      t.integer "points"
      t.decimal "true_shooting_percentage", precision: 6, scale: 5
      t.decimal "effective_fg_percentage", precision: 6, scale: 5
      t.decimal "three_pt_attempt_rate", precision: 6, scale: 5
      t.decimal "free_throw_rate", precision: 6, scale: 5
      t.decimal "offensive_rebound_rate", precision: 6, scale: 5
      t.decimal "defensive_rebound_rate", precision: 6, scale: 5
      t.decimal "rebound_rate", precision: 6, scale: 5
      t.decimal "assist_rate", precision: 6, scale: 5
      t.decimal "steal_rate", precision: 6, scale: 5
      t.decimal "block_rate", precision: 6, scale: 5
      t.decimal "turnover_rate", precision: 6, scale: 5
      t.decimal "offensive_rating", precision: 6, scale: 5
      t.decimal "defensive_rating", precision: 6, scale: 5
      t.index ["game_id", "home"], name: "index_team_games_on_game_id_and_home", unique: true
      t.index ["game_id"], name: "index_team_games_on_game_id"
      t.index ["team_id", "game_id"], name: "index_team_games_on_team_id_and_game_id", unique: true
      t.index ["team_id"], name: "index_team_games_on_team_id"

      t.timestamps
    end
  end
end
