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

ActiveRecord::Schema[7.0].define(version: 2023_05_19_134708) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "games", force: :cascade do |t|
    t.string "url", null: false
    t.datetime "start_time", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "season_id", null: false
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
