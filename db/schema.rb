# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 2023_05_19_172825) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "games", force: :cascade do |t|
    t.string "url", null: false
    t.datetime "start_time", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
  end

  create_table "seasons", force: :cascade do |t|
    t.integer "year", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.index ["year"], name: "index_seasons_on_year"
  end

  create_table "team_games", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "game_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "home"
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
  end

  create_table "team_seasons", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "season_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["season_id"], name: "index_team_seasons_on_season_id"
    t.index ["team_id", "season_id"], name: "index_team_seasons_on_team_id_and_season_id", unique: true
    t.index ["team_id"], name: "index_team_seasons_on_team_id"
  end

  create_table "teams", force: :cascade do |t|
    t.string "school"
    t.string "nickname"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.string "location"
    t.index ["school"], name: "index_teams_on_school", unique: true
  end

end
