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

ActiveRecord::Schema[7.1].define(version: 2024_02_02_020844) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "games", force: :cascade do |t|
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
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "minutes"
    t.index ["season_id"], name: "index_games_on_season_id"
  end

  create_table "good_job_batches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.jsonb "serialized_properties"
    t.text "on_finish"
    t.text "on_success"
    t.text "on_discard"
    t.text "callback_queue_name"
    t.integer "callback_priority"
    t.datetime "enqueued_at"
    t.datetime "discarded_at"
    t.datetime "finished_at"
  end

  create_table "good_job_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "active_job_id", null: false
    t.text "job_class"
    t.text "queue_name"
    t.jsonb "serialized_params"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.text "error"
    t.integer "error_event", limit: 2
    t.index ["active_job_id", "created_at"], name: "index_good_job_executions_on_active_job_id_and_created_at"
  end

  create_table "good_job_processes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "state"
  end

  create_table "good_job_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "key"
    t.jsonb "value"
    t.index ["key"], name: "index_good_job_settings_on_key", unique: true
  end

  create_table "good_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "queue_name"
    t.integer "priority"
    t.jsonb "serialized_params"
    t.datetime "scheduled_at"
    t.datetime "performed_at"
    t.datetime "finished_at"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "active_job_id"
    t.text "concurrency_key"
    t.text "cron_key"
    t.uuid "retried_good_job_id"
    t.datetime "cron_at"
    t.uuid "batch_id"
    t.uuid "batch_callback_id"
    t.boolean "is_discrete"
    t.integer "executions_count"
    t.text "job_class"
    t.integer "error_event", limit: 2
    t.text "labels", array: true
    t.index ["active_job_id", "created_at"], name: "index_good_jobs_on_active_job_id_and_created_at"
    t.index ["batch_callback_id"], name: "index_good_jobs_on_batch_callback_id", where: "(batch_callback_id IS NOT NULL)"
    t.index ["batch_id"], name: "index_good_jobs_on_batch_id", where: "(batch_id IS NOT NULL)"
    t.index ["concurrency_key"], name: "index_good_jobs_on_concurrency_key_when_unfinished", where: "(finished_at IS NULL)"
    t.index ["cron_key", "created_at"], name: "index_good_jobs_on_cron_key_and_created_at_cond", where: "(cron_key IS NOT NULL)"
    t.index ["cron_key", "cron_at"], name: "index_good_jobs_on_cron_key_and_cron_at_cond", unique: true, where: "(cron_key IS NOT NULL)"
    t.index ["finished_at"], name: "index_good_jobs_jobs_on_finished_at", where: "((retried_good_job_id IS NULL) AND (finished_at IS NOT NULL))"
    t.index ["labels"], name: "index_good_jobs_on_labels", where: "(labels IS NOT NULL)", using: :gin
    t.index ["priority", "created_at"], name: "index_good_job_jobs_for_candidate_lookup", where: "(finished_at IS NULL)"
    t.index ["priority", "created_at"], name: "index_good_jobs_jobs_on_priority_created_at_when_unfinished", order: { priority: "DESC NULLS LAST" }, where: "(finished_at IS NULL)"
    t.index ["queue_name", "scheduled_at"], name: "index_good_jobs_on_queue_name_and_scheduled_at", where: "(finished_at IS NULL)"
    t.index ["scheduled_at"], name: "index_good_jobs_on_scheduled_at", where: "(finished_at IS NULL)"
  end

  create_table "seasons", force: :cascade do |t|
    t.integer "year", null: false
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "average_efficiency", precision: 6, scale: 5
    t.decimal "average_pace", precision: 6, scale: 5
    t.index ["year"], name: "index_seasons_on_year", unique: true
  end

  create_table "team_games", force: :cascade do |t|
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
    t.decimal "offensive_rating", precision: 6, scale: 3
    t.decimal "defensive_rating", precision: 6, scale: 3
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "team_season_id", null: false
    t.index ["game_id", "home"], name: "index_team_games_on_game_id_and_home", unique: true
    t.index ["game_id"], name: "index_team_games_on_game_id"
    t.index ["team_id", "game_id"], name: "index_team_games_on_team_id_and_game_id", unique: true
    t.index ["team_id"], name: "index_team_games_on_team_id"
    t.index ["team_season_id"], name: "index_team_games_on_team_season_id"
  end

  create_table "team_seasons", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "season_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "offensive_efficiency", precision: 6, scale: 3
    t.decimal "defensive_efficiency", precision: 6, scale: 3
    t.decimal "pace", precision: 6, scale: 3
    t.decimal "adj_offensive_efficiency", precision: 6, scale: 3
    t.decimal "adj_defensive_efficiency", precision: 6, scale: 3
    t.decimal "adj_pace", precision: 6, scale: 3
    t.decimal "rating", precision: 6, scale: 3
    t.index ["season_id"], name: "index_team_seasons_on_season_id"
    t.index ["team_id", "season_id"], name: "index_team_seasons_on_team_id_and_season_id", unique: true
    t.index ["team_id"], name: "index_team_seasons_on_team_id"
  end

  create_table "teams", force: :cascade do |t|
    t.string "school"
    t.string "nickname"
    t.string "url"
    t.string "location"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "secondary_name"
    t.string "home_venue"
    t.index ["school"], name: "index_teams_on_school", unique: true
  end

end
