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

ActiveRecord::Schema[7.1].define(version: 2025_07_13_142057) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "bet_recommendations", force: :cascade do |t|
    t.bigint "game_id", null: false
    t.bigint "prediction_id", null: false
    t.bigint "game_odd_id", null: false
    t.string "bet_type", null: false, comment: "'moneyline', 'spread', or 'total'"
    t.string "team", comment: "'home', 'away', 'over', 'under'"
    t.float "vegas_line", comment: "point spread or total; nil for moneyline"
    t.integer "vegas_odds", null: false, comment: "payout in American odds (e.g. -110, +150)"
    t.float "model_value", null: false, comment: "model-predicted value (spread, total, or win %)"
    t.float "ev", null: false, comment: "expected value (unit-neutral, e.g. +0.07 = +7%)"
    t.float "confidence", comment: "optional: model confidence (0.0–1.0 or 0–100 scale)"
    t.boolean "recommended", default: false, null: false, comment: "whether the bet is actionable"
    t.string "result", comment: "'win', 'loss', 'push'"
    t.float "payout", comment: "net return in units, e.g. +0.91, -1.00"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "ratings_config_version_id"
    t.boolean "current", default: false
    t.index ["game_id"], name: "index_bet_recommendations_on_game_id"
    t.index ["game_odd_id"], name: "index_bet_recommendations_on_game_odd_id"
    t.index ["prediction_id", "game_odd_id", "bet_type"], name: "index_bet_recommendations_on_prediction_game_odd_bet_type", unique: true
    t.index ["prediction_id"], name: "index_bet_recommendations_on_prediction_id"
    t.index ["ratings_config_version_id"], name: "index_bet_recommendations_on_ratings_config_version_id"
  end

  create_table "bookmaker_odds", force: :cascade do |t|
    t.bigint "game_id", null: false
    t.string "bookmaker", null: false
    t.datetime "fetched_at", null: false
    t.string "market", null: false
    t.string "team_name"
    t.string "team_side"
    t.decimal "value"
    t.integer "odds"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id"], name: "index_bookmaker_odds_on_game_id"
  end

  create_table "conferences", force: :cascade do |t|
    t.string "name", null: false
    t.string "abbreviation"
    t.string "slug"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_conferences_on_name"
    t.index ["slug"], name: "index_conferences_on_slug"
  end

  create_table "game_odds", force: :cascade do |t|
    t.bigint "game_id", null: false
    t.datetime "fetched_at", null: false
    t.integer "moneyline_home"
    t.integer "moneyline_away"
    t.decimal "spread_point"
    t.integer "spread_home_odds"
    t.integer "spread_away_odds"
    t.decimal "total_points"
    t.integer "total_over_odds"
    t.integer "total_under_odds"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id"], name: "index_game_odds_on_game_id"
  end

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
    t.boolean "in_conference", default: false
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

  create_table "predictions", force: :cascade do |t|
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
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "home_team_snapshot_id"
    t.bigint "away_team_snapshot_id"
    t.decimal "home_win_probability", precision: 5, scale: 4
    t.decimal "vegas_spread", precision: 6, scale: 3
    t.decimal "vegas_total", precision: 6, scale: 3
    t.bigint "ratings_config_version_id"
    t.index ["away_team_snapshot_id"], name: "index_predictions_on_away_team_snapshot_id"
    t.index ["game_id"], name: "index_predictions_on_game_id"
    t.index ["home_team_snapshot_id"], name: "index_predictions_on_home_team_snapshot_id"
    t.index ["ratings_config_version_id"], name: "index_predictions_on_ratings_config_version_id"
  end

  create_table "ratings_config_versions", force: :cascade do |t|
    t.jsonb "config", null: false
    t.string "description"
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "current", default: false
    t.index ["current"], name: "index_ratings_config_versions_on_current", unique: true, where: "(current IS TRUE)"
    t.index ["name"], name: "index_ratings_config_versions_on_name", unique: true
  end

  create_table "seasons", force: :cascade do |t|
    t.integer "year", null: false
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "average_efficiency", precision: 6, scale: 3
    t.decimal "average_pace", precision: 6, scale: 3
    t.decimal "efficiency_std_deviation", precision: 6, scale: 3
    t.decimal "pace_std_deviation", precision: 6, scale: 3
    t.decimal "avg_adj_offensive_efficiency", precision: 6, scale: 3
    t.decimal "stddev_adj_offensive_efficiency", precision: 6, scale: 3
    t.decimal "avg_adj_defensive_efficiency", precision: 6, scale: 3
    t.decimal "stddev_adj_defensive_efficiency", precision: 6, scale: 3
    t.decimal "avg_adj_effective_fg_percentage", precision: 6, scale: 5
    t.decimal "stddev_adj_effective_fg_percentage", precision: 6, scale: 5
    t.decimal "avg_adj_turnover_rate", precision: 6, scale: 5
    t.decimal "stddev_adj_turnover_rate", precision: 6, scale: 5
    t.decimal "avg_adj_offensive_rebound_rate", precision: 6, scale: 5
    t.decimal "stddev_adj_offensive_rebound_rate", precision: 6, scale: 5
    t.decimal "avg_adj_free_throw_rate", precision: 6, scale: 5
    t.decimal "stddev_adj_free_throw_rate", precision: 6, scale: 5
    t.decimal "avg_adj_effective_fg_percentage_allowed", precision: 6, scale: 5
    t.decimal "stddev_adj_effective_fg_percentage_allowed", precision: 6, scale: 5
    t.decimal "avg_adj_turnover_rate_forced", precision: 6, scale: 5
    t.decimal "stddev_adj_turnover_rate_forced", precision: 6, scale: 5
    t.decimal "avg_adj_defensive_rebound_rate", precision: 6, scale: 5
    t.decimal "stddev_adj_defensive_rebound_rate", precision: 6, scale: 5
    t.decimal "avg_adj_free_throw_rate_allowed", precision: 6, scale: 5
    t.decimal "stddev_adj_free_throw_rate_allowed", precision: 6, scale: 5
    t.decimal "avg_adj_three_pt_proficiency", precision: 6, scale: 5
    t.decimal "stddev_adj_three_pt_proficiency", precision: 6, scale: 5
    t.boolean "current", default: false
    t.string "name"
    t.index ["current"], name: "index_seasons_on_current", unique: true, where: "(current IS TRUE)"
    t.index ["year"], name: "index_seasons_on_year", unique: true
  end

  create_table "team_aliases", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.string "value", null: false
    t.string "source"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id"], name: "index_team_aliases_on_team_id"
    t.index ["value", "source"], name: "index_team_aliases_on_value_and_source", unique: true
  end

  create_table "team_conferences", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "conference_id", null: false
    t.bigint "start_season_id", null: false
    t.bigint "end_season_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conference_id"], name: "index_team_conferences_on_conference_id"
    t.index ["end_season_id"], name: "index_team_conferences_on_end_season_id"
    t.index ["start_season_id"], name: "index_team_conferences_on_start_season_id"
    t.index ["team_id", "start_season_id", "end_season_id"], name: "index_team_conferences_on_team_and_season_range", unique: true
    t.index ["team_id"], name: "index_team_conferences_on_team_id"
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
    t.bigint "opponent_team_season_id"
    t.decimal "three_pt_proficiency", precision: 6, scale: 5
    t.index ["game_id", "home"], name: "index_team_games_on_game_id_and_home", unique: true
    t.index ["game_id"], name: "index_team_games_on_game_id"
    t.index ["opponent_team_season_id"], name: "index_team_games_on_opponent_team_season_id"
    t.index ["team_id", "game_id"], name: "index_team_games_on_team_id_and_game_id", unique: true
    t.index ["team_id"], name: "index_team_games_on_team_id"
    t.index ["team_season_id"], name: "index_team_games_on_team_season_id"
  end

  create_table "team_offseason_profiles", force: :cascade do |t|
    t.bigint "team_season_id", null: false
    t.integer "recruiting_class_rank"
    t.float "recruiting_score"
    t.float "returning_minutes_pct"
    t.float "returning_bpm_total"
    t.integer "lost_starters"
    t.boolean "coaching_change"
    t.float "manual_adjustment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_season_id"], name: "index_team_offseason_profiles_on_team_season_id"
  end

  create_table "team_rating_snapshots", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "season_id", null: false
    t.bigint "team_season_id", null: false
    t.date "snapshot_date", null: false
    t.decimal "rating", precision: 6, scale: 3
    t.decimal "adj_offensive_efficiency", precision: 6, scale: 3
    t.decimal "adj_defensive_efficiency", precision: 6, scale: 3
    t.decimal "adj_pace", precision: 6, scale: 3
    t.jsonb "stats", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "ratings_config_version_id"
    t.index ["rating", "snapshot_date"], name: "index_team_rating_snapshots_on_rating_and_snapshot_date"
    t.index ["ratings_config_version_id"], name: "index_team_rating_snapshots_on_ratings_config_version_id"
    t.index ["season_id"], name: "index_team_rating_snapshots_on_season_id"
    t.index ["team_id", "season_id", "snapshot_date"], name: "idx_on_team_id_season_id_snapshot_date_8de7607130"
    t.index ["team_id"], name: "index_team_rating_snapshots_on_team_id"
    t.index ["team_season_id"], name: "index_team_rating_snapshots_on_team_season_id"
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
    t.decimal "effective_fg_percentage", precision: 6, scale: 5
    t.decimal "turnover_rate", precision: 6, scale: 5
    t.decimal "offensive_rebound_rate", precision: 6, scale: 5
    t.decimal "free_throw_rate", precision: 6, scale: 5
    t.decimal "three_pt_attempt_rate", precision: 6, scale: 5
    t.decimal "adj_effective_fg_percentage", precision: 6, scale: 5
    t.decimal "adj_effective_fg_percentage_allowed", precision: 6, scale: 5
    t.decimal "adj_turnover_rate", precision: 6, scale: 5
    t.decimal "adj_turnover_rate_forced", precision: 6, scale: 5
    t.decimal "adj_offensive_rebound_rate", precision: 6, scale: 5
    t.decimal "adj_defensive_rebound_rate", precision: 6, scale: 5
    t.decimal "adj_free_throw_rate", precision: 6, scale: 5
    t.decimal "adj_free_throw_rate_allowed", precision: 6, scale: 5
    t.decimal "home_offense_boost", precision: 6, scale: 3
    t.decimal "home_defense_boost", precision: 6, scale: 3
    t.decimal "away_offense_penalty", precision: 6, scale: 3
    t.decimal "away_defense_penalty", precision: 6, scale: 3
    t.decimal "offensive_efficiency_std_dev", precision: 6, scale: 3
    t.decimal "defensive_efficiency_std_dev", precision: 6, scale: 3
    t.decimal "preseason_adj_offensive_efficiency", precision: 6, scale: 3
    t.decimal "preseason_adj_defensive_efficiency", precision: 6, scale: 3
    t.decimal "preseason_adj_pace", precision: 6, scale: 3
    t.decimal "offensive_efficiency_volatility", precision: 6, scale: 3
    t.decimal "defensive_efficiency_volatility", precision: 6, scale: 3
    t.decimal "pace_volatility", precision: 6, scale: 3
    t.integer "overall_rank"
    t.integer "pace_rank"
    t.integer "adj_offensive_efficiency_rank"
    t.integer "adj_defensive_efficiency_rank"
    t.integer "adj_effective_fg_percentage_rank"
    t.integer "adj_turnover_rate_rank"
    t.integer "adj_offensive_rebound_rate_rank"
    t.integer "adj_free_throw_rate_rank"
    t.integer "adj_effective_fg_percentage_allowed_rank"
    t.integer "adj_turnover_rate_forced_rank"
    t.integer "adj_defensive_rebound_rate_rank"
    t.integer "adj_free_throw_rate_allowed_rank"
    t.decimal "total_home_boost", precision: 6, scale: 3
    t.decimal "total_volatility", precision: 6, scale: 3
    t.integer "wins", default: 0
    t.integer "losses", default: 0
    t.integer "adj_pace_rank"
    t.decimal "adj_three_pt_proficiency", precision: 6, scale: 5
    t.decimal "adj_three_pt_proficiency_allowed", precision: 6, scale: 5
    t.integer "adj_three_pt_proficiency_rank"
    t.integer "adj_three_pt_proficiency_allowed_rank"
    t.decimal "three_pt_proficiency", precision: 6, scale: 5
    t.integer "conference_wins", default: 0
    t.integer "conference_losses", default: 0
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
    t.string "home_venue"
    t.string "slug"
    t.string "primary_color"
    t.string "short_name"
    t.string "the_odds_api_team_id"
    t.index ["school"], name: "index_teams_on_school", unique: true
    t.index ["slug"], name: "index_teams_on_slug", unique: true
    t.index ["the_odds_api_team_id"], name: "index_teams_on_the_odds_api_team_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "admin", default: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "bet_recommendations", "game_odds"
  add_foreign_key "bet_recommendations", "games"
  add_foreign_key "bet_recommendations", "predictions"
  add_foreign_key "bet_recommendations", "ratings_config_versions"
  add_foreign_key "bookmaker_odds", "games"
  add_foreign_key "game_odds", "games"
  add_foreign_key "predictions", "ratings_config_versions"
  add_foreign_key "predictions", "team_rating_snapshots", column: "away_team_snapshot_id"
  add_foreign_key "predictions", "team_rating_snapshots", column: "home_team_snapshot_id"
  add_foreign_key "team_aliases", "teams"
  add_foreign_key "team_conferences", "conferences"
  add_foreign_key "team_conferences", "seasons", column: "end_season_id"
  add_foreign_key "team_conferences", "seasons", column: "start_season_id"
  add_foreign_key "team_conferences", "teams"
  add_foreign_key "team_games", "team_seasons", column: "opponent_team_season_id"
  add_foreign_key "team_rating_snapshots", "ratings_config_versions"
  add_foreign_key "team_rating_snapshots", "seasons"
  add_foreign_key "team_rating_snapshots", "team_seasons"
  add_foreign_key "team_rating_snapshots", "teams"
end
