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

ActiveRecord::Schema[8.1].define(version: 2026_10_10_163200) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "bet_recommendations", force: :cascade do |t|
    t.string "bet_type", null: false, comment: "'moneyline', 'spread', or 'total'"
    t.float "confidence", comment: "optional: model confidence (0.0–1.0 or 0–100 scale)"
    t.datetime "created_at", null: false
    t.boolean "current", default: false
    t.float "ev", null: false, comment: "expected value (unit-neutral, e.g. +0.07 = +7%)"
    t.bigint "game_id", null: false
    t.bigint "game_odd_id", null: false
    t.float "model_value", null: false, comment: "model-predicted value (spread, total, or win %)"
    t.float "payout", comment: "net return in units, e.g. +0.91, -1.00"
    t.bigint "prediction_id", null: false
    t.bigint "ratings_config_version_id"
    t.boolean "recommended", default: false, null: false, comment: "whether the bet is actionable"
    t.string "result", comment: "'win', 'loss', 'push'"
    t.string "team", comment: "'home', 'away', 'over', 'under'"
    t.datetime "updated_at", null: false
    t.float "vegas_line", comment: "point spread or total; nil for moneyline"
    t.integer "vegas_odds", null: false, comment: "payout in American odds (e.g. -110, +150)"
    t.index ["game_id", "bet_type"], name: "index_bet_recommendations_on_game_and_type_current_true", unique: true, where: "(current IS TRUE)"
    t.index ["game_id"], name: "index_bet_recommendations_on_game_id"
    t.index ["game_odd_id"], name: "index_bet_recommendations_on_game_odd_id"
    t.index ["prediction_id", "game_odd_id", "bet_type"], name: "index_bet_recommendations_on_prediction_game_odd_bet_type", unique: true
    t.index ["prediction_id"], name: "index_bet_recommendations_on_prediction_id"
    t.index ["ratings_config_version_id"], name: "index_bet_recommendations_on_ratings_config_version_id"
  end

  create_table "bookmaker_odds", force: :cascade do |t|
    t.string "bookmaker", null: false
    t.datetime "created_at", null: false
    t.datetime "fetched_at", null: false
    t.bigint "game_id", null: false
    t.string "market", null: false
    t.integer "odds"
    t.string "team_name"
    t.string "team_side"
    t.datetime "updated_at", null: false
    t.decimal "value"
    t.index ["game_id"], name: "index_bookmaker_odds_on_game_id"
  end

  create_table "coaching_changes", force: :cascade do |t|
    t.string "coach_name"
    t.datetime "created_at", null: false
    t.string "destination_school"
    t.string "discovery_coach_name"
    t.string "discovery_former_coach"
    t.boolean "discovery_present"
    t.bigint "discovery_previous_team_id"
    t.string "discovery_school"
    t.bigint "discovery_team_id"
    t.integer "effective_year", null: false
    t.boolean "full_season_head_coach", default: false, null: false
    t.string "previous_role"
    t.string "previous_school"
    t.boolean "previous_season_d1", default: false, null: false
    t.bigint "previous_team_id"
    t.integer "previous_year"
    t.string "status", default: "pending", null: false
    t.bigint "team_id"
    t.datetime "updated_at", null: false
    t.index ["effective_year", "discovery_school"], name: "unique_coaching_discovery_school", unique: true, where: "(discovery_school IS NOT NULL)"
    t.index ["effective_year", "status"], name: "index_coaching_changes_on_effective_year_and_status"
    t.index ["previous_team_id"], name: "index_coaching_changes_on_previous_team_id"
    t.index ["team_id", "effective_year"], name: "unique_confirmed_coaching_destination", unique: true, where: "((status)::text = 'confirmed'::text)"
    t.index ["team_id"], name: "index_coaching_changes_on_team_id"
    t.check_constraint "effective_year >= 1 AND effective_year <= 9999", name: "coaching_effective_year"
    t.check_constraint "previous_year >= 1 AND previous_year <= 9999", name: "coaching_previous_year"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'confirmed'::character varying, 'rejected'::character varying]::text[])", name: "coaching_status"
  end

  create_table "coaching_reviews", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "ready", default: false, null: false
    t.datetime "updated_at", null: false
    t.integer "year", null: false
    t.index ["year"], name: "index_coaching_reviews_on_year", unique: true
    t.check_constraint "year >= 1 AND year <= 9999", name: "coaching_review_year"
  end

  create_table "conferences", force: :cascade do |t|
    t.string "abbreviation"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_conferences_on_name"
    t.index ["slug"], name: "index_conferences_on_slug"
  end

  create_table "game_odds", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "fetched_at", null: false
    t.bigint "game_id", null: false
    t.integer "moneyline_away"
    t.integer "moneyline_home"
    t.integer "spread_away_odds"
    t.integer "spread_home_odds"
    t.decimal "spread_point"
    t.integer "total_over_odds"
    t.decimal "total_points"
    t.integer "total_under_odds"
    t.datetime "updated_at", null: false
    t.index ["game_id"], name: "index_game_odds_on_game_id_unique", unique: true
  end

  create_table "game_sync_dates", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "imported_rows"
    t.datetime "last_attempt_at"
    t.text "last_error"
    t.date "schedule_date", null: false
    t.bigint "season_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["season_id", "schedule_date"], name: "index_game_sync_dates_on_season_id_and_schedule_date", unique: true
    t.index ["season_id"], name: "index_game_sync_dates_on_season_id"
  end

  create_table "games", force: :cascade do |t|
    t.string "away_team_name", null: false
    t.integer "away_team_score"
    t.datetime "created_at", null: false
    t.string "home_team_name", null: false
    t.integer "home_team_score"
    t.boolean "in_conference", default: false
    t.integer "minutes"
    t.boolean "neutral"
    t.decimal "possessions", precision: 4, scale: 1
    t.bigint "season_id", null: false
    t.datetime "start_time", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.string "venue_confidence", default: "unknown", null: false
    t.string "venue_name"
    t.string "venue_source"
    t.string "venue_type", default: "unknown", null: false
    t.index ["home_team_name", "away_team_name", "start_time"], name: "index_games_on_teams_and_start_time"
    t.index ["season_id"], name: "index_games_on_season_id"
    t.index ["url"], name: "index_games_on_url"
    t.index ["venue_confidence"], name: "index_games_on_venue_confidence"
    t.index ["venue_type"], name: "index_games_on_venue_type"
  end

  create_table "good_job_batches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "callback_priority"
    t.text "callback_queue_name"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "discarded_at"
    t.datetime "enqueued_at"
    t.datetime "finished_at"
    t.datetime "jobs_finished_at"
    t.text "on_discard"
    t.text "on_finish"
    t.text "on_success"
    t.jsonb "serialized_properties"
    t.datetime "updated_at", null: false
  end

  create_table "good_job_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "active_job_id", null: false
    t.datetime "created_at", null: false
    t.interval "duration"
    t.text "error"
    t.text "error_backtrace", array: true
    t.integer "error_event", limit: 2
    t.datetime "finished_at"
    t.text "job_class"
    t.uuid "process_id"
    t.text "queue_name"
    t.datetime "scheduled_at"
    t.jsonb "serialized_params"
    t.datetime "updated_at", null: false
    t.index ["active_job_id", "created_at"], name: "index_good_job_executions_on_active_job_id_and_created_at"
    t.index ["process_id", "created_at"], name: "index_good_job_executions_on_process_id_and_created_at"
  end

  create_table "good_job_processes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "lock_type", limit: 2
    t.jsonb "state"
    t.datetime "updated_at", null: false
  end

  create_table "good_job_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "key"
    t.datetime "updated_at", null: false
    t.jsonb "value"
    t.index ["key"], name: "index_good_job_settings_on_key", unique: true
  end

  create_table "good_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "active_job_id"
    t.uuid "batch_callback_id"
    t.uuid "batch_id"
    t.text "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "cron_at"
    t.text "cron_key"
    t.text "error"
    t.integer "error_event", limit: 2
    t.integer "executions_count"
    t.datetime "finished_at"
    t.boolean "is_discrete"
    t.text "job_class"
    t.text "labels", array: true
    t.datetime "locked_at"
    t.uuid "locked_by_id"
    t.datetime "performed_at"
    t.integer "priority"
    t.text "queue_name"
    t.uuid "retried_good_job_id"
    t.datetime "scheduled_at"
    t.jsonb "serialized_params"
    t.datetime "updated_at", null: false
    t.index ["active_job_id", "created_at"], name: "index_good_jobs_on_active_job_id_and_created_at"
    t.index ["batch_callback_id"], name: "index_good_jobs_on_batch_callback_id", where: "(batch_callback_id IS NOT NULL)"
    t.index ["batch_id"], name: "index_good_jobs_on_batch_id", where: "(batch_id IS NOT NULL)"
    t.index ["concurrency_key", "created_at"], name: "index_good_jobs_on_concurrency_key_and_created_at"
    t.index ["concurrency_key"], name: "index_good_jobs_on_concurrency_key_when_unfinished", where: "(finished_at IS NULL)"
    t.index ["cron_key", "created_at"], name: "index_good_jobs_on_cron_key_and_created_at_cond", where: "(cron_key IS NOT NULL)"
    t.index ["cron_key", "cron_at"], name: "index_good_jobs_on_cron_key_and_cron_at_cond", unique: true, where: "(cron_key IS NOT NULL)"
    t.index ["finished_at"], name: "index_good_jobs_jobs_on_finished_at_only", where: "(finished_at IS NOT NULL)"
    t.index ["job_class"], name: "index_good_jobs_on_job_class"
    t.index ["labels"], name: "index_good_jobs_on_labels", where: "(labels IS NOT NULL)", using: :gin
    t.index ["locked_by_id"], name: "index_good_jobs_on_locked_by_id", where: "(locked_by_id IS NOT NULL)"
    t.index ["priority", "created_at"], name: "index_good_job_jobs_for_candidate_lookup", where: "(finished_at IS NULL)"
    t.index ["priority", "created_at"], name: "index_good_jobs_jobs_on_priority_created_at_when_unfinished", order: { priority: "DESC NULLS LAST" }, where: "(finished_at IS NULL)"
    t.index ["priority", "scheduled_at"], name: "index_good_jobs_on_priority_scheduled_at_unfinished_unlocked", where: "((finished_at IS NULL) AND (locked_by_id IS NULL))"
    t.index ["queue_name", "scheduled_at"], name: "index_good_jobs_on_queue_name_and_scheduled_at", where: "(finished_at IS NULL)"
    t.index ["scheduled_at"], name: "index_good_jobs_on_scheduled_at", where: "(finished_at IS NULL)"
  end

  create_table "predictions", force: :cascade do |t|
    t.decimal "away_defensive_efficiency", precision: 6, scale: 3
    t.decimal "away_defensive_efficiency_error", precision: 6, scale: 3
    t.decimal "away_offensive_efficiency", precision: 6, scale: 3
    t.decimal "away_offensive_efficiency_error", precision: 6, scale: 3
    t.decimal "away_score", precision: 6, scale: 3
    t.bigint "away_team_snapshot_id"
    t.jsonb "calculation_context", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "forecast_kind", default: "legacy_unverified", null: false
    t.datetime "forecast_start_time"
    t.bigint "game_id", null: false
    t.datetime "generated_at"
    t.decimal "home_defensive_efficiency", precision: 6, scale: 3
    t.decimal "home_defensive_efficiency_error", precision: 6, scale: 3
    t.decimal "home_offensive_efficiency", precision: 6, scale: 3
    t.decimal "home_offensive_efficiency_error", precision: 6, scale: 3
    t.decimal "home_score", precision: 6, scale: 3
    t.bigint "home_team_snapshot_id"
    t.decimal "home_win_probability", precision: 5, scale: 4
    t.date "input_cutoff"
    t.decimal "pace", precision: 6, scale: 3
    t.decimal "pace_error", precision: 6, scale: 3
    t.bigint "ratings_config_version_id"
    t.string "revision_key"
    t.datetime "updated_at", null: false
    t.decimal "vegas_spread", precision: 6, scale: 3
    t.decimal "vegas_total", precision: 6, scale: 3
    t.index ["away_team_snapshot_id"], name: "index_predictions_on_away_team_snapshot_id"
    t.index ["game_id", "created_at"], name: "index_predictions_on_game_id_and_created_at"
    t.index ["game_id", "ratings_config_version_id", "revision_key"], name: "index_predictions_on_revision", unique: true
    t.index ["game_id"], name: "index_predictions_on_game_id"
    t.index ["home_team_snapshot_id"], name: "index_predictions_on_home_team_snapshot_id"
    t.index ["ratings_config_version_id"], name: "index_predictions_on_ratings_config_version_id"
  end

  create_table "preseason_priors", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "inputs", null: false
    t.jsonb "outputs", null: false
    t.bigint "ratings_config_version_id", null: false
    t.bigint "team_season_id", null: false
    t.datetime "updated_at", null: false
    t.index ["ratings_config_version_id"], name: "index_preseason_priors_on_ratings_config_version_id"
    t.index ["team_season_id", "ratings_config_version_id"], name: "index_preseason_priors_on_team_season_and_config", unique: true
    t.index ["team_season_id"], name: "index_preseason_priors_on_team_season_id"
  end

  create_table "ratings_config_versions", force: :cascade do |t|
    t.jsonb "config", null: false
    t.datetime "created_at", null: false
    t.boolean "current", default: false
    t.string "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["current"], name: "index_ratings_config_versions_on_current", unique: true, where: "(current IS TRUE)"
    t.index ["name"], name: "index_ratings_config_versions_on_name", unique: true
  end

  create_table "seasons", force: :cascade do |t|
    t.decimal "average_efficiency", precision: 6, scale: 3
    t.decimal "average_pace", precision: 6, scale: 3
    t.decimal "avg_adj_defensive_efficiency", precision: 6, scale: 3
    t.decimal "avg_adj_defensive_rebound_rate", precision: 6, scale: 5
    t.decimal "avg_adj_effective_fg_percentage", precision: 6, scale: 5
    t.decimal "avg_adj_effective_fg_percentage_allowed", precision: 6, scale: 5
    t.decimal "avg_adj_free_throw_rate", precision: 6, scale: 5
    t.decimal "avg_adj_free_throw_rate_allowed", precision: 6, scale: 5
    t.decimal "avg_adj_offensive_efficiency", precision: 6, scale: 3
    t.decimal "avg_adj_offensive_rebound_rate", precision: 6, scale: 5
    t.decimal "avg_adj_three_pt_proficiency", precision: 6, scale: 5
    t.decimal "avg_adj_turnover_rate", precision: 6, scale: 5
    t.decimal "avg_adj_turnover_rate_forced", precision: 6, scale: 5
    t.datetime "created_at", null: false
    t.boolean "current", default: false
    t.decimal "efficiency_std_deviation", precision: 6, scale: 3
    t.date "end_date", null: false
    t.string "name"
    t.decimal "pace_std_deviation", precision: 6, scale: 3
    t.jsonb "participation_review", default: {}, null: false
    t.bigint "preseason_revision_id"
    t.date "start_date", null: false
    t.decimal "stddev_adj_defensive_efficiency", precision: 6, scale: 3
    t.decimal "stddev_adj_defensive_rebound_rate", precision: 6, scale: 5
    t.decimal "stddev_adj_effective_fg_percentage", precision: 6, scale: 5
    t.decimal "stddev_adj_effective_fg_percentage_allowed", precision: 6, scale: 5
    t.decimal "stddev_adj_free_throw_rate", precision: 6, scale: 5
    t.decimal "stddev_adj_free_throw_rate_allowed", precision: 6, scale: 5
    t.decimal "stddev_adj_offensive_efficiency", precision: 6, scale: 3
    t.decimal "stddev_adj_offensive_rebound_rate", precision: 6, scale: 5
    t.decimal "stddev_adj_three_pt_proficiency", precision: 6, scale: 5
    t.decimal "stddev_adj_turnover_rate", precision: 6, scale: 5
    t.decimal "stddev_adj_turnover_rate_forced", precision: 6, scale: 5
    t.datetime "updated_at", null: false
    t.integer "year", null: false
    t.index ["current"], name: "index_seasons_on_current", unique: true, where: "(current IS TRUE)"
    t.index ["preseason_revision_id"], name: "index_seasons_on_preseason_revision_id"
    t.index ["year"], name: "index_seasons_on_year", unique: true
  end

  create_table "team_aliases", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "source"
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.string "value", null: false
    t.index ["team_id"], name: "index_team_aliases_on_team_id"
    t.index ["value", "source"], name: "index_team_aliases_on_value_and_source", unique: true
  end

  create_table "team_conferences", force: :cascade do |t|
    t.bigint "conference_id", null: false
    t.datetime "created_at", null: false
    t.bigint "end_season_id"
    t.bigint "start_season_id", null: false
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["conference_id"], name: "index_team_conferences_on_conference_id"
    t.index ["end_season_id"], name: "index_team_conferences_on_end_season_id"
    t.index ["start_season_id"], name: "index_team_conferences_on_start_season_id"
    t.index ["team_id", "start_season_id"], name: "index_team_conferences_on_team_and_start_season", unique: true
    t.index ["team_id"], name: "index_team_conferences_on_team_id"
  end

  create_table "team_games", force: :cascade do |t|
    t.decimal "assist_rate", precision: 6, scale: 5
    t.integer "assists"
    t.decimal "block_rate", precision: 6, scale: 5
    t.integer "blocks"
    t.datetime "created_at", null: false
    t.decimal "defensive_rating", precision: 6, scale: 3
    t.decimal "defensive_rebound_rate", precision: 6, scale: 5
    t.integer "defensive_rebounds"
    t.decimal "effective_fg_percentage", precision: 6, scale: 5
    t.integer "field_goals_attempted"
    t.integer "field_goals_made"
    t.decimal "field_goals_percentage", precision: 6, scale: 5
    t.integer "fouls"
    t.decimal "free_throw_rate", precision: 6, scale: 5
    t.integer "free_throws_attempted"
    t.integer "free_throws_made"
    t.decimal "free_throws_percentage", precision: 6, scale: 5
    t.bigint "game_id", null: false
    t.boolean "home", default: false
    t.integer "minutes"
    t.decimal "offensive_rating", precision: 6, scale: 3
    t.decimal "offensive_rebound_rate", precision: 6, scale: 5
    t.integer "offensive_rebounds"
    t.bigint "opponent_team_season_id"
    t.integer "points"
    t.decimal "rebound_rate", precision: 6, scale: 5
    t.integer "rebounds"
    t.decimal "steal_rate", precision: 6, scale: 5
    t.integer "steals"
    t.bigint "team_id", null: false
    t.bigint "team_season_id", null: false
    t.decimal "three_pt_attempt_rate", precision: 6, scale: 5
    t.integer "three_pt_attempted"
    t.integer "three_pt_made"
    t.decimal "three_pt_percentage", precision: 6, scale: 5
    t.decimal "three_pt_proficiency", precision: 6, scale: 5
    t.decimal "true_shooting_percentage", precision: 6, scale: 5
    t.decimal "turnover_rate", precision: 6, scale: 5
    t.integer "turnovers"
    t.integer "two_pt_attempted"
    t.integer "two_pt_made"
    t.decimal "two_pt_percentage", precision: 6, scale: 5
    t.datetime "updated_at", null: false
    t.index ["game_id", "home"], name: "index_team_games_on_game_id_and_home", unique: true
    t.index ["game_id"], name: "index_team_games_on_game_id"
    t.index ["opponent_team_season_id"], name: "index_team_games_on_opponent_team_season_id"
    t.index ["team_id", "game_id"], name: "index_team_games_on_team_id_and_game_id", unique: true
    t.index ["team_id"], name: "index_team_games_on_team_id"
    t.index ["team_season_id"], name: "index_team_games_on_team_season_id"
  end

  create_table "team_offseason_profiles", force: :cascade do |t|
    t.boolean "coaching_change"
    t.datetime "created_at", null: false
    t.jsonb "input_units", default: {}, null: false
    t.integer "lost_starters"
    t.float "manual_adjustment"
    t.text "manual_adjustment_reason"
    t.date "observed_on"
    t.integer "recruiting_class_rank"
    t.float "recruiting_score"
    t.float "returning_bpm_total"
    t.float "returning_minutes_pct"
    t.text "source_reference"
    t.bigint "team_season_id", null: false
    t.datetime "updated_at", null: false
    t.index ["team_season_id"], name: "index_team_offseason_profiles_on_team_season_id", unique: true
  end

  create_table "team_rating_snapshots", force: :cascade do |t|
    t.decimal "adj_defensive_efficiency", precision: 6, scale: 3
    t.decimal "adj_offensive_efficiency", precision: 6, scale: 3
    t.decimal "adj_pace", precision: 6, scale: 3
    t.datetime "created_at", null: false
    t.decimal "rating", precision: 6, scale: 3
    t.bigint "ratings_config_version_id"
    t.bigint "season_id", null: false
    t.date "snapshot_date", null: false
    t.jsonb "stats", default: {}, null: false
    t.bigint "team_id", null: false
    t.bigint "team_season_id", null: false
    t.datetime "updated_at", null: false
    t.index ["rating", "snapshot_date"], name: "index_team_rating_snapshots_on_rating_and_snapshot_date"
    t.index ["ratings_config_version_id"], name: "index_team_rating_snapshots_on_ratings_config_version_id"
    t.index ["season_id"], name: "index_team_rating_snapshots_on_season_id"
    t.index ["team_id", "season_id", "snapshot_date", "ratings_config_version_id"], name: "idx_trs_on_team_season_date_rcv_unique", unique: true
    t.index ["team_id"], name: "index_team_rating_snapshots_on_team_id"
    t.index ["team_season_id", "ratings_config_version_id", "snapshot_date"], name: "index_team_rating_snapshots_on_team_season_config_date"
    t.index ["team_season_id"], name: "index_team_rating_snapshots_on_team_season_id"
  end

  create_table "team_seasons", force: :cascade do |t|
    t.decimal "adj_defensive_efficiency", precision: 6, scale: 3
    t.integer "adj_defensive_efficiency_rank"
    t.decimal "adj_defensive_rebound_rate", precision: 6, scale: 5
    t.integer "adj_defensive_rebound_rate_rank"
    t.decimal "adj_effective_fg_percentage", precision: 6, scale: 5
    t.decimal "adj_effective_fg_percentage_allowed", precision: 6, scale: 5
    t.integer "adj_effective_fg_percentage_allowed_rank"
    t.integer "adj_effective_fg_percentage_rank"
    t.decimal "adj_free_throw_rate", precision: 6, scale: 5
    t.decimal "adj_free_throw_rate_allowed", precision: 6, scale: 5
    t.integer "adj_free_throw_rate_allowed_rank"
    t.integer "adj_free_throw_rate_rank"
    t.decimal "adj_offensive_efficiency", precision: 6, scale: 3
    t.integer "adj_offensive_efficiency_rank"
    t.decimal "adj_offensive_rebound_rate", precision: 6, scale: 5
    t.integer "adj_offensive_rebound_rate_rank"
    t.decimal "adj_pace", precision: 6, scale: 3
    t.integer "adj_pace_rank"
    t.decimal "adj_three_pt_proficiency", precision: 6, scale: 5
    t.decimal "adj_three_pt_proficiency_allowed", precision: 6, scale: 5
    t.integer "adj_three_pt_proficiency_allowed_rank"
    t.integer "adj_three_pt_proficiency_rank"
    t.decimal "adj_turnover_rate", precision: 6, scale: 5
    t.decimal "adj_turnover_rate_forced", precision: 6, scale: 5
    t.integer "adj_turnover_rate_forced_rank"
    t.integer "adj_turnover_rate_rank"
    t.decimal "away_defense_penalty", precision: 6, scale: 3
    t.decimal "away_offense_penalty", precision: 6, scale: 3
    t.integer "conference_losses", default: 0
    t.integer "conference_wins", default: 0
    t.datetime "created_at", null: false
    t.decimal "defensive_efficiency", precision: 6, scale: 3
    t.decimal "defensive_efficiency_std_dev", precision: 6, scale: 3
    t.decimal "defensive_efficiency_volatility", precision: 6, scale: 3
    t.decimal "effective_fg_percentage", precision: 6, scale: 5
    t.decimal "free_throw_rate", precision: 6, scale: 5
    t.decimal "home_defense_boost", precision: 6, scale: 3
    t.decimal "home_offense_boost", precision: 6, scale: 3
    t.integer "losses", default: 0
    t.decimal "offensive_efficiency", precision: 6, scale: 3
    t.decimal "offensive_efficiency_std_dev", precision: 6, scale: 3
    t.decimal "offensive_efficiency_volatility", precision: 6, scale: 3
    t.decimal "offensive_rebound_rate", precision: 6, scale: 5
    t.integer "overall_rank"
    t.decimal "pace", precision: 6, scale: 3
    t.integer "pace_rank"
    t.decimal "pace_volatility", precision: 6, scale: 3
    t.decimal "preseason_adj_defensive_efficiency", precision: 6, scale: 3
    t.decimal "preseason_adj_offensive_efficiency", precision: 6, scale: 3
    t.decimal "preseason_adj_pace", precision: 6, scale: 3
    t.bigint "preseason_prior_id"
    t.decimal "rating", precision: 6, scale: 3
    t.bigint "ratings_config_version_id"
    t.bigint "season_id", null: false
    t.bigint "team_id", null: false
    t.decimal "three_pt_attempt_rate", precision: 6, scale: 5
    t.decimal "three_pt_proficiency", precision: 6, scale: 5
    t.decimal "total_home_boost", precision: 6, scale: 3
    t.decimal "total_volatility", precision: 6, scale: 3
    t.decimal "turnover_rate", precision: 6, scale: 5
    t.datetime "updated_at", null: false
    t.integer "wins", default: 0
    t.index ["preseason_prior_id"], name: "index_team_seasons_on_preseason_prior_id"
    t.index ["ratings_config_version_id"], name: "index_team_seasons_on_ratings_config_version_id"
    t.index ["season_id"], name: "index_team_seasons_on_season_id"
    t.index ["team_id", "season_id"], name: "index_team_seasons_on_team_id_and_season_id", unique: true
    t.index ["team_id"], name: "index_team_seasons_on_team_id"
  end

  create_table "teams", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "home_venue"
    t.string "location"
    t.string "nickname"
    t.string "primary_color"
    t.string "school"
    t.string "short_name"
    t.string "slug"
    t.string "the_odds_api_team_id"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["school"], name: "index_teams_on_school", unique: true
    t.index ["slug"], name: "index_teams_on_slug", unique: true
    t.index ["the_odds_api_team_id"], name: "index_teams_on_the_odds_api_team_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "bet_recommendations", "game_odds"
  add_foreign_key "bet_recommendations", "games"
  add_foreign_key "bet_recommendations", "predictions"
  add_foreign_key "bet_recommendations", "ratings_config_versions"
  add_foreign_key "bookmaker_odds", "games"
  add_foreign_key "coaching_changes", "teams"
  add_foreign_key "coaching_changes", "teams", column: "discovery_previous_team_id"
  add_foreign_key "coaching_changes", "teams", column: "discovery_team_id"
  add_foreign_key "coaching_changes", "teams", column: "previous_team_id"
  add_foreign_key "game_odds", "games"
  add_foreign_key "game_sync_dates", "seasons"
  add_foreign_key "predictions", "ratings_config_versions"
  add_foreign_key "predictions", "team_rating_snapshots", column: "away_team_snapshot_id"
  add_foreign_key "predictions", "team_rating_snapshots", column: "home_team_snapshot_id"
  add_foreign_key "preseason_priors", "ratings_config_versions"
  add_foreign_key "preseason_priors", "team_seasons"
  add_foreign_key "seasons", "ratings_config_versions", column: "preseason_revision_id"
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
  add_foreign_key "team_seasons", "preseason_priors"
  add_foreign_key "team_seasons", "ratings_config_versions"
end
