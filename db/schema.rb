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

ActiveRecord::Schema[8.1].define(version: 2026_10_30_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.index ["game_id", "bet_type"], name: "index_bet_recommendations_on_game_and_type_current_true", unique: true, where: "(current IS TRUE)"
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

  create_table "cbbd_review_captures", force: :cascade do |t|
    t.bigint "cbbd_review_run_id", null: false
    t.string "capture_id", null: false
    t.binary "body", null: false
    t.jsonb "metadata", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cbbd_review_run_id", "capture_id"], name: "idx_on_cbbd_review_run_id_capture_id_29ffd9cbe6", unique: true
    t.index ["cbbd_review_run_id"], name: "index_cbbd_review_captures_on_cbbd_review_run_id"
  end

  create_table "cbbd_review_comparisons", force: :cascade do |t|
    t.bigint "cbbd_review_run_id", null: false
    t.integer "version", null: false
    t.jsonb "replay", null: false
    t.jsonb "report", null: false
    t.string "artifact_digest", null: false
    t.jsonb "draft", default: {}, null: false
    t.integer "draft_revision", default: 0, null: false
    t.bigint "identity_mapping_decision_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cbbd_review_run_id", "version"], name: "idx_on_cbbd_review_run_id_version_0c5d8e333d", unique: true
    t.index ["cbbd_review_run_id"], name: "index_cbbd_review_comparisons_on_cbbd_review_run_id"
    t.index ["identity_mapping_decision_id"], name: "index_cbbd_review_comparisons_on_identity_mapping_decision_id"
  end

  create_table "cbbd_review_runs", force: :cascade do |t|
    t.bigint "season_id", null: false
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.integer "maximum_requests", null: false
    t.integer "retries", null: false
    t.string "status", default: "queued", null: false
    t.string "failure"
    t.jsonb "manifest", default: {}, null: false
    t.jsonb "normalized_replay"
    t.string "evidence_digest"
    t.bigint "active_comparison_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["season_id"], name: "index_cbbd_review_runs_on_season_id"
  end

  create_table "cbbd_sync_runs", force: :cascade do |t|
    t.bigint "season_id", null: false
    t.bigint "ratings_config_version_id", null: false
    t.date "season_start_date", null: false
    t.date "season_end_date", null: false
    t.date "schedule_date", null: false
    t.datetime "bucket", null: false
    t.integer "maximum_requests", null: false
    t.integer "retries", null: false
    t.bigint "past_acquisition_id"
    t.string "past_status", default: "pending", null: false
    t.jsonb "past_report", default: {}, null: false
    t.bigint "future_acquisition_id"
    t.string "future_status", default: "pending", null: false
    t.jsonb "future_report", default: {}, null: false
    t.string "analytics_status", default: "pending", null: false
    t.string "analytics_job_id"
    t.string "analytics_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["future_acquisition_id"], name: "index_cbbd_sync_runs_on_future_acquisition_id"
    t.index ["past_acquisition_id"], name: "index_cbbd_sync_runs_on_past_acquisition_id"
    t.index ["ratings_config_version_id"], name: "index_cbbd_sync_runs_on_ratings_config_version_id"
    t.index ["season_id", "bucket"], name: "index_cbbd_sync_runs_on_season_id_and_bucket", unique: true
    t.index ["season_id"], name: "index_cbbd_sync_runs_on_season_id"
  end

  create_table "coaching_changes", force: :cascade do |t|
    t.bigint "team_id"
    t.integer "effective_year", null: false
    t.string "coach_name"
    t.string "destination_school"
    t.bigint "previous_team_id"
    t.string "previous_school"
    t.integer "previous_year"
    t.string "previous_role"
    t.boolean "full_season_head_coach", default: false, null: false
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "previous_season_d1", default: false, null: false
    t.string "discovery_school"
    t.string "discovery_coach_name"
    t.string "discovery_former_coach"
    t.boolean "discovery_present"
    t.bigint "discovery_team_id"
    t.bigint "discovery_previous_team_id"
    t.index ["effective_year", "discovery_school"], name: "unique_coaching_discovery_school", unique: true, where: "(discovery_school IS NOT NULL)"
    t.index ["effective_year", "status"], name: "index_coaching_changes_on_effective_year_and_status"
    t.index ["previous_team_id"], name: "index_coaching_changes_on_previous_team_id"
    t.index ["team_id", "effective_year"], name: "unique_confirmed_coaching_destination", unique: true, where: "((status)::text = 'confirmed'::text)"
    t.index ["team_id"], name: "index_coaching_changes_on_team_id"
    t.check_constraint "effective_year >= 1 AND effective_year <= 9999", name: "coaching_effective_year"
    t.check_constraint "previous_year >= 1 AND previous_year <= 9999", name: "coaching_previous_year"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'confirmed'::character varying::text, 'rejected'::character varying::text])", name: "coaching_status"
  end

  create_table "coaching_reviews", force: :cascade do |t|
    t.integer "year", null: false
    t.boolean "ready", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "discovery_status", default: "idle", null: false
    t.datetime "discovered_at"
    t.text "discovery_error"
    t.index ["year"], name: "index_coaching_reviews_on_year", unique: true
    t.check_constraint "year >= 1 AND year <= 9999", name: "coaching_review_year"
  end

  create_table "conference_external_identities", force: :cascade do |t|
    t.bigint "conference_id", null: false
    t.string "provider", null: false
    t.string "external_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conference_id"], name: "index_conference_external_identities_on_conference_id"
    t.index ["provider", "external_id"], name: "idx_on_provider_external_id_4998627b48", unique: true
  end

  create_table "conferences", force: :cascade do |t|
    t.string "name", null: false
    t.string "abbreviation"
    t.string "slug"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "sports_reference_slugs", default: [], null: false, array: true
    t.index ["name"], name: "index_conferences_on_name"
    t.index ["slug"], name: "index_conferences_on_slug"
  end

  create_table "departure_acquisitions", force: :cascade do |t|
    t.bigint "departure_batch_id", null: false
    t.bigint "predecessor_id"
    t.string "status", default: "queued", null: false
    t.jsonb "plan", default: {}, null: false
    t.jsonb "manifest", default: {}, null: false
    t.jsonb "dataset", default: {}, null: false
    t.jsonb "evidence", default: {}, null: false
    t.string "failure"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["departure_batch_id"], name: "index_departure_acquisitions_on_departure_batch_id"
    t.index ["predecessor_id"], name: "index_departure_acquisitions_on_predecessor_id"
  end

  create_table "departure_approvals", force: :cascade do |t|
    t.bigint "departure_validation_id", null: false
    t.bigint "user_id"
    t.bigint "predecessor_id"
    t.string "reviewed_by", null: false
    t.datetime "reviewed_at", null: false
    t.string "reason", default: "Approved by admin", null: false
    t.jsonb "document", null: false
    t.string "review_hash", null: false
    t.text "signature"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["departure_validation_id"], name: "index_departure_approvals_on_departure_validation_id", unique: true
    t.index ["predecessor_id"], name: "index_departure_approvals_on_predecessor_id"
    t.index ["user_id"], name: "index_departure_approvals_on_user_id"
  end

  create_table "departure_batches", force: :cascade do |t|
    t.bigint "season_id", null: false
    t.bigint "revision_id"
    t.bigint "predecessor_id"
    t.string "status", default: "draft", null: false
    t.jsonb "plan", default: {}, null: false
    t.jsonb "decisions", default: [], null: false
    t.jsonb "acknowledgement", default: {}, null: false
    t.string "correction_reason"
    t.string "reviewed_by"
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["predecessor_id"], name: "index_departure_batches_on_predecessor_id"
    t.index ["revision_id"], name: "index_departure_batches_on_revision_id"
    t.index ["season_id"], name: "index_departure_batches_on_season_id"
  end

  create_table "departure_capture_observations", force: :cascade do |t|
    t.bigint "departure_source_capture_id", null: false
    t.bigint "departure_acquisition_id", null: false
    t.string "source_id", null: false
    t.jsonb "metadata", null: false
    t.string "extraction_version", null: false
    t.index ["departure_acquisition_id", "source_id"], name: "idx_departure_observation_identity", unique: true
    t.index ["departure_acquisition_id"], name: "idx_departure_observation_origin"
    t.index ["departure_source_capture_id"], name: "idx_departure_observation_capture"
  end

  create_table "departure_dataset_normalizations", force: :cascade do |t|
    t.string "identity", null: false
    t.string "status", default: "running", null: false
    t.jsonb "header", null: false
    t.jsonb "source_normalization_ids", default: {}, null: false
    t.string "dataset_revision"
    t.jsonb "summary", default: {}, null: false
    t.index ["identity"], name: "index_departure_dataset_normalizations_on_identity", unique: true
  end

  create_table "departure_dataset_rows", force: :cascade do |t|
    t.bigint "departure_dataset_normalization_id", null: false
    t.string "kind", null: false
    t.integer "ordinal", null: false
    t.json "fact", null: false
    t.index ["departure_dataset_normalization_id", "kind", "ordinal"], name: "idx_departure_dataset_row_order", unique: true
    t.index ["departure_dataset_normalization_id"], name: "idx_departure_dataset_row_parent"
  end

  create_table "departure_normalized_rows", force: :cascade do |t|
    t.bigint "departure_source_normalization_id", null: false
    t.integer "ordinal", null: false
    t.string "row_key", null: false
    t.bigint "provider_team_id"
    t.bigint "provider_player_id"
    t.json "fact", null: false
    t.index ["departure_source_normalization_id", "ordinal"], name: "idx_departure_row_order", unique: true
    t.index ["departure_source_normalization_id", "row_key"], name: "idx_departure_row_identity", unique: true
    t.index ["departure_source_normalization_id"], name: "idx_departure_row_source"
  end

  create_table "departure_proposals", force: :cascade do |t|
    t.bigint "departure_validation_id", null: false
    t.bigint "team_id", null: false
    t.jsonb "input", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["departure_validation_id", "team_id"], name: "idx_on_departure_validation_id_team_id_9e7285e173", unique: true
    t.index ["departure_validation_id"], name: "index_departure_proposals_on_departure_validation_id"
    t.index ["team_id"], name: "index_departure_proposals_on_team_id"
  end

  create_table "departure_source_captures", force: :cascade do |t|
    t.string "sha256", null: false
    t.bigint "byte_size", null: false
    t.binary "body", null: false
    t.index ["sha256"], name: "index_departure_source_captures_on_sha256", unique: true
  end

  create_table "departure_source_normalizations", force: :cascade do |t|
    t.bigint "departure_source_capture_id", null: false
    t.string "identity", null: false
    t.jsonb "contract", null: false
    t.string "status", default: "running", null: false
    t.string "rows_digest"
    t.integer "row_count", default: 0, null: false
    t.text "failure"
    t.index ["departure_source_capture_id"], name: "idx_departure_normalization_capture"
    t.index ["identity"], name: "index_departure_source_normalizations_on_identity", unique: true
  end

  create_table "departure_validations", force: :cascade do |t|
    t.bigint "departure_batch_id", null: false
    t.bigint "departure_acquisition_id", null: false
    t.bigint "departure_dataset_normalization_id"
    t.bigint "offseason_input_revision_id"
    t.string "status", default: "queued", null: false
    t.string "validator_version", null: false
    t.jsonb "report", default: {}, null: false
    t.jsonb "choices", default: {}, null: false
    t.string "dependency_hash"
    t.jsonb "artifacts", default: {}, null: false
    t.text "publication_receipt"
    t.text "certificate"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["departure_acquisition_id"], name: "index_departure_validations_on_departure_acquisition_id"
    t.index ["departure_batch_id"], name: "index_departure_validations_on_departure_batch_id"
    t.index ["departure_dataset_normalization_id"], name: "idx_on_departure_dataset_normalization_id_e41300d490"
    t.index ["offseason_input_revision_id"], name: "index_departure_validations_on_offseason_input_revision_id"
  end

  create_table "game_external_identities", force: :cascade do |t|
    t.bigint "game_id", null: false
    t.string "provider", null: false
    t.string "external_id", null: false
    t.datetime "superseded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id"], name: "index_game_external_identities_on_game_id"
    t.index ["provider", "external_id"], name: "index_game_external_identities_on_provider_and_external_id", unique: true
    t.index ["provider", "game_id"], name: "index_game_external_identities_on_active_provider_game", unique: true, where: "(superseded_at IS NULL)"
  end

  create_table "game_observations", force: :cascade do |t|
    t.bigint "game_id"
    t.string "provider"
    t.string "external_game_id"
    t.string "semantic_profile"
    t.string "outcome", null: false
    t.text "reason"
    t.boolean "accepted", default: false, null: false
    t.jsonb "normalized_payload", default: {}, null: false
    t.jsonb "raw_payload", default: {}, null: false
    t.string "payload_digest"
    t.datetime "captured_at"
    t.datetime "source_updated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "scoring_review_id"
    t.index ["game_id", "accepted", "id"], name: "index_game_observations_on_game_id_and_accepted_and_id"
    t.index ["game_id"], name: "index_game_observations_on_game_id"
    t.index ["provider", "external_game_id"], name: "index_game_observations_on_provider_and_external_game_id"
    t.index ["scoring_review_id"], name: "index_game_observations_on_scoring_review_id"
    t.index ["scoring_review_id"], name: "index_one_accepted_observation_per_scoring_review", unique: true, where: "(accepted = true)"
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
    t.index ["game_id"], name: "index_game_odds_on_game_id_unique", unique: true
  end

  create_table "game_schedule_reviews", force: :cascade do |t|
    t.bigint "season_id", null: false
    t.bigint "schedule_refresh_run_id", null: false
    t.bigint "game_id", null: false
    t.bigint "source_observation_id", null: false
    t.bigint "prior_observation_id", null: false
    t.bigint "reviewed_by_id", null: false
    t.string "choice", null: false
    t.string "selected_external_id", null: false
    t.string "ignored_external_id", null: false
    t.string "ignored_fingerprint", null: false
    t.string "comparison_fingerprint", null: false
    t.jsonb "selected_payload", null: false
    t.jsonb "selected_schedule", null: false
    t.jsonb "participants", null: false
    t.string "reason", default: "Approved by admin", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id"], name: "index_game_schedule_reviews_on_game_id"
    t.index ["ignored_external_id"], name: "index_game_schedule_reviews_on_ignored_external_id"
    t.index ["ignored_external_id"], name: "index_one_retired_schedule_game_key", unique: true, where: "((selected_external_id)::text <> (ignored_external_id)::text)"
    t.index ["prior_observation_id"], name: "index_game_schedule_reviews_on_prior_observation_id"
    t.index ["reviewed_by_id"], name: "index_game_schedule_reviews_on_reviewed_by_id"
    t.index ["schedule_refresh_run_id"], name: "index_game_schedule_reviews_on_schedule_refresh_run_id"
    t.index ["season_id"], name: "index_game_schedule_reviews_on_season_id"
    t.index ["source_observation_id"], name: "index_game_schedule_reviews_on_source_observation_id", unique: true
  end

  create_table "game_scoring_reviews", force: :cascade do |t|
    t.bigint "season_id", null: false
    t.bigint "schedule_refresh_run_id", null: false
    t.bigint "source_observation_id", null: false
    t.bigint "reviewed_by_id", null: false
    t.string "source_fingerprint", null: false
    t.string "reason", default: "Approved by admin", null: false
    t.jsonb "choices", default: {}, null: false
    t.jsonb "approved_payload", default: {}, null: false
    t.jsonb "participants", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reviewed_by_id"], name: "index_game_scoring_reviews_on_reviewed_by_id"
    t.index ["schedule_refresh_run_id"], name: "index_game_scoring_reviews_on_schedule_refresh_run_id"
    t.index ["season_id"], name: "index_game_scoring_reviews_on_season_id"
    t.index ["source_fingerprint"], name: "index_game_scoring_reviews_on_source_fingerprint", unique: true
    t.index ["source_observation_id"], name: "index_game_scoring_reviews_on_source_observation_id", unique: true
  end

  create_table "game_sync_dates", force: :cascade do |t|
    t.bigint "season_id", null: false
    t.date "schedule_date", null: false
    t.string "status", default: "pending", null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "last_attempt_at"
    t.datetime "completed_at"
    t.integer "imported_rows"
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "provider", default: "sports_reference", null: false
    t.string "contract_version", default: "legacy-unscoped", null: false
    t.string "semantic_profile", default: "sports-reference-legacy-v1", null: false
    t.string "adapter_revision", default: "legacy-unscoped", null: false
    t.index ["season_id", "schedule_date", "provider", "contract_version", "semantic_profile", "adapter_revision"], name: "index_game_sync_dates_on_provider_scope", unique: true
    t.index ["season_id"], name: "index_game_sync_dates_on_season_id"
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
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "minutes"
    t.boolean "in_conference", default: false
    t.string "venue_type", default: "unknown", null: false
    t.string "venue_source"
    t.string "venue_confidence", default: "unknown", null: false
    t.string "venue_name"
    t.index ["home_team_name", "away_team_name", "start_time"], name: "index_games_on_teams_and_start_time"
    t.index ["season_id"], name: "index_games_on_season_id"
    t.index ["url"], name: "index_games_on_url"
    t.index ["venue_confidence"], name: "index_games_on_venue_confidence"
    t.index ["venue_type"], name: "index_games_on_venue_type"
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
    t.datetime "jobs_finished_at"
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
    t.text "error_backtrace", array: true
    t.uuid "process_id"
    t.interval "duration"
    t.index ["active_job_id", "created_at"], name: "index_good_job_executions_on_active_job_id_and_created_at"
    t.index ["process_id", "created_at"], name: "index_good_job_executions_on_process_id_and_created_at"
  end

  create_table "good_job_processes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "state"
    t.integer "lock_type", limit: 2
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
    t.uuid "locked_by_id"
    t.datetime "locked_at"
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

  create_table "identity_mapping_decisions", force: :cascade do |t|
    t.string "request_digest", null: false
    t.string "comparison_fingerprint", null: false
    t.string "post_apply_fingerprint", null: false
    t.string "reviewer", null: false
    t.text "reason", null: false
    t.jsonb "request", null: false
    t.jsonb "result", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["request_digest"], name: "index_identity_mapping_decisions_on_request_digest", unique: true
  end

  create_table "offseason_input_revisions", force: :cascade do |t|
    t.bigint "season_id", null: false
    t.string "kind", null: false
    t.string "version", null: false
    t.string "input_hash", null: false
    t.string "dataset_hash", null: false
    t.string "review_hash", null: false
    t.bigint "predecessor_id"
    t.text "reason", null: false
    t.jsonb "payload", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["predecessor_id"], name: "index_offseason_input_revisions_on_predecessor_id"
    t.index ["season_id", "kind", "input_hash"], name: "index_offseason_revisions_identity", unique: true
    t.index ["season_id", "kind", "version"], name: "index_offseason_revisions_version", unique: true
    t.index ["season_id"], name: "index_offseason_input_revisions_on_season_id"
  end

  create_table "offseason_readiness_operations", force: :cascade do |t|
    t.bigint "season_id", null: false
    t.bigint "actor_id", null: false
    t.bigint "offseason_readiness_review_id"
    t.string "action", null: false
    t.string "status", default: "queued", null: false
    t.jsonb "inputs", default: {}, null: false
    t.jsonb "report", default: {}, null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_offseason_readiness_operations_on_actor_id"
    t.index ["offseason_readiness_review_id"], name: "index_readiness_operations_on_review_id"
    t.index ["season_id"], name: "index_offseason_readiness_operations_on_season_id"
  end

  create_table "offseason_readiness_reviews", force: :cascade do |t|
    t.bigint "season_id", null: false
    t.bigint "ratings_config_version_id"
    t.bigint "reviewer_id", null: false
    t.string "fingerprint", null: false
    t.jsonb "report", null: false
    t.jsonb "acknowledgement", default: {}, null: false
    t.jsonb "deferrals", default: {}, null: false
    t.jsonb "results", default: {}, null: false
    t.jsonb "attempts", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ratings_config_version_id"], name: "index_offseason_readiness_reviews_on_ratings_config_version_id"
    t.index ["reviewer_id"], name: "index_offseason_readiness_reviews_on_reviewer_id"
    t.index ["season_id"], name: "index_offseason_readiness_reviews_on_season_id"
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
    t.float "home_win_probability"
    t.decimal "vegas_spread", precision: 6, scale: 3
    t.decimal "vegas_total", precision: 6, scale: 3
    t.bigint "ratings_config_version_id"
    t.jsonb "calculation_context", default: {}, null: false
    t.string "forecast_kind", default: "legacy_unverified", null: false
    t.datetime "generated_at"
    t.datetime "forecast_start_time"
    t.date "input_cutoff"
    t.string "revision_key"
    t.index ["away_team_snapshot_id"], name: "index_predictions_on_away_team_snapshot_id"
    t.index ["game_id", "created_at"], name: "index_predictions_on_game_id_and_created_at"
    t.index ["game_id", "ratings_config_version_id", "revision_key"], name: "index_predictions_on_revision", unique: true
    t.index ["game_id"], name: "index_predictions_on_game_id"
    t.index ["home_team_snapshot_id"], name: "index_predictions_on_home_team_snapshot_id"
    t.index ["ratings_config_version_id"], name: "index_predictions_on_ratings_config_version_id"
  end

  create_table "preseason_priors", force: :cascade do |t|
    t.bigint "team_season_id", null: false
    t.bigint "ratings_config_version_id", null: false
    t.jsonb "inputs", null: false
    t.jsonb "outputs", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ratings_config_version_id"], name: "index_preseason_priors_on_ratings_config_version_id"
    t.index ["team_season_id", "ratings_config_version_id"], name: "index_preseason_priors_on_team_season_and_config", unique: true
    t.index ["team_season_id"], name: "index_preseason_priors_on_team_season_id"
  end

  create_table "preseason_publications", force: :cascade do |t|
    t.bigint "season_id", null: false
    t.bigint "ratings_config_version_id", null: false
    t.bigint "reviewer_id", null: false
    t.string "mode", null: false
    t.string "status", default: "review", null: false
    t.string "fingerprint", null: false
    t.jsonb "report", null: false
    t.jsonb "acknowledgement", default: {}, null: false
    t.jsonb "result", default: {}, null: false
    t.text "error_message"
    t.datetime "queued_at"
    t.datetime "started_at"
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ratings_config_version_id"], name: "index_preseason_publications_on_ratings_config_version_id"
    t.index ["reviewer_id"], name: "index_preseason_publications_on_reviewer_id"
    t.index ["season_id"], name: "index_preseason_publications_on_season_id"
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

  create_table "recruiting_batches", force: :cascade do |t|
    t.bigint "season_id", null: false
    t.bigint "revision_id"
    t.string "status", default: "queued", null: false
    t.integer "source_year", null: false
    t.string "source_status"
    t.string "dataset_revision"
    t.text "extract_bytes"
    t.text "snapshot_bytes"
    t.text "coverage_note"
    t.text "failure_message"
    t.text "next_url"
    t.integer "page_count", default: 0, null: false
    t.string "reviewed_by"
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["revision_id"], name: "index_recruiting_batches_on_revision_id"
    t.index ["season_id"], name: "index_recruiting_batches_on_season_id"
  end

  create_table "recruiting_entries", force: :cascade do |t|
    t.bigint "recruiting_batch_id", null: false
    t.bigint "team_id"
    t.integer "row_number", null: false
    t.string "source_label"
    t.string "provider_team_id"
    t.text "source_url"
    t.decimal "source_rank"
    t.decimal "class_points"
    t.decimal "average_rating"
    t.decimal "commit_count"
    t.jsonb "source_row"
    t.jsonb "source_errors", default: [], null: false
    t.boolean "excluded", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["recruiting_batch_id", "row_number"], name: "index_recruiting_entries_on_recruiting_batch_id_and_row_number", unique: true
    t.index ["recruiting_batch_id"], name: "index_recruiting_entries_on_recruiting_batch_id"
    t.index ["team_id"], name: "index_recruiting_entries_on_team_id"
  end

  create_table "schedule_deferrals", force: :cascade do |t|
    t.bigint "season_id", null: false
    t.bigint "requested_by_id", null: false
    t.text "reason", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["requested_by_id"], name: "index_schedule_deferrals_on_requested_by_id"
    t.index ["season_id"], name: "index_schedule_deferrals_on_season_id"
  end

  create_table "schedule_refresh_runs", force: :cascade do |t|
    t.bigint "season_id", null: false
    t.bigint "requested_by_id", null: false
    t.bigint "retry_of_id"
    t.string "provider", null: false
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.jsonb "requested_dates", default: [], null: false
    t.integer "max_requests"
    t.integer "retries"
    t.string "status", default: "queued", null: false
    t.jsonb "report", default: {}, null: false
    t.text "error"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "mode", default: "upcoming", null: false
    t.boolean "rescan", default: false, null: false
    t.index ["requested_by_id"], name: "index_schedule_refresh_runs_on_requested_by_id"
    t.index ["retry_of_id"], name: "index_schedule_refresh_runs_on_retry_of_id", unique: true
    t.index ["season_id"], name: "index_schedule_refresh_runs_on_season_id"
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
    t.jsonb "participation_review", default: {}, null: false
    t.bigint "preseason_revision_id"
    t.jsonb "membership_proposal", default: {}, null: false
    t.jsonb "membership_corrections", default: [], null: false
    t.bigint "selected_preseason_model_id"
    t.integer "preseason_selection_generation", default: 0, null: false
    t.index ["current"], name: "index_seasons_on_current", unique: true, where: "(current IS TRUE)"
    t.index ["preseason_revision_id"], name: "index_seasons_on_preseason_revision_id"
    t.index ["selected_preseason_model_id"], name: "index_seasons_on_selected_preseason_model_id"
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
    t.index ["team_id", "start_season_id"], name: "index_team_conferences_on_team_and_start_season", unique: true
    t.index ["team_id"], name: "index_team_conferences_on_team_id"
  end

  create_table "team_external_identities", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.string "provider", null: false
    t.string "external_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "external_id"], name: "index_team_external_identities_on_provider_and_external_id", unique: true
    t.index ["team_id"], name: "index_team_external_identities_on_team_id"
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
    t.text "source_reference"
    t.date "observed_on"
    t.jsonb "input_units", default: {}, null: false
    t.text "manual_adjustment_reason"
    t.bigint "recruiting_revision_id"
    t.bigint "departure_revision_id"
    t.index ["departure_revision_id"], name: "index_team_offseason_profiles_on_departure_revision_id"
    t.index ["recruiting_revision_id"], name: "index_team_offseason_profiles_on_recruiting_revision_id"
    t.index ["team_season_id"], name: "index_team_offseason_profiles_on_team_season_id", unique: true
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
    t.index ["team_id", "season_id", "snapshot_date", "ratings_config_version_id"], name: "idx_trs_on_team_season_date_rcv_unique", unique: true
    t.index ["team_id"], name: "index_team_rating_snapshots_on_team_id"
    t.index ["team_season_id", "ratings_config_version_id", "snapshot_date"], name: "index_team_rating_snapshots_on_team_season_config_date"
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
    t.bigint "ratings_config_version_id"
    t.bigint "preseason_prior_id"
    t.jsonb "rating_anchors", default: {}, null: false
    t.index ["preseason_prior_id"], name: "index_team_seasons_on_preseason_prior_id"
    t.index ["ratings_config_version_id"], name: "index_team_seasons_on_ratings_config_version_id"
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
  add_foreign_key "cbbd_review_captures", "cbbd_review_runs"
  add_foreign_key "cbbd_review_comparisons", "cbbd_review_runs"
  add_foreign_key "cbbd_review_comparisons", "identity_mapping_decisions"
  add_foreign_key "cbbd_review_runs", "cbbd_review_comparisons", column: "active_comparison_id"
  add_foreign_key "cbbd_review_runs", "seasons"
  add_foreign_key "cbbd_sync_runs", "cbbd_review_runs", column: "future_acquisition_id"
  add_foreign_key "cbbd_sync_runs", "cbbd_review_runs", column: "past_acquisition_id"
  add_foreign_key "cbbd_sync_runs", "ratings_config_versions"
  add_foreign_key "cbbd_sync_runs", "seasons"
  add_foreign_key "coaching_changes", "teams"
  add_foreign_key "coaching_changes", "teams", column: "discovery_previous_team_id"
  add_foreign_key "coaching_changes", "teams", column: "discovery_team_id"
  add_foreign_key "coaching_changes", "teams", column: "previous_team_id"
  add_foreign_key "conference_external_identities", "conferences"
  add_foreign_key "departure_acquisitions", "departure_acquisitions", column: "predecessor_id"
  add_foreign_key "departure_acquisitions", "departure_batches"
  add_foreign_key "departure_approvals", "departure_validations"
  add_foreign_key "departure_approvals", "offseason_input_revisions", column: "predecessor_id"
  add_foreign_key "departure_approvals", "users"
  add_foreign_key "departure_batches", "departure_batches", column: "predecessor_id"
  add_foreign_key "departure_batches", "offseason_input_revisions", column: "revision_id"
  add_foreign_key "departure_batches", "seasons"
  add_foreign_key "departure_capture_observations", "departure_acquisitions"
  add_foreign_key "departure_capture_observations", "departure_source_captures"
  add_foreign_key "departure_dataset_rows", "departure_dataset_normalizations"
  add_foreign_key "departure_normalized_rows", "departure_source_normalizations"
  add_foreign_key "departure_proposals", "departure_validations"
  add_foreign_key "departure_proposals", "teams"
  add_foreign_key "departure_source_normalizations", "departure_source_captures"
  add_foreign_key "departure_validations", "departure_acquisitions"
  add_foreign_key "departure_validations", "departure_batches"
  add_foreign_key "departure_validations", "departure_dataset_normalizations"
  add_foreign_key "departure_validations", "offseason_input_revisions"
  add_foreign_key "game_external_identities", "games"
  add_foreign_key "game_observations", "game_scoring_reviews", column: "scoring_review_id"
  add_foreign_key "game_observations", "games"
  add_foreign_key "game_odds", "games"
  add_foreign_key "game_schedule_reviews", "game_observations", column: "prior_observation_id"
  add_foreign_key "game_schedule_reviews", "game_observations", column: "source_observation_id"
  add_foreign_key "game_schedule_reviews", "games"
  add_foreign_key "game_schedule_reviews", "schedule_refresh_runs"
  add_foreign_key "game_schedule_reviews", "seasons"
  add_foreign_key "game_schedule_reviews", "users", column: "reviewed_by_id"
  add_foreign_key "game_scoring_reviews", "game_observations", column: "source_observation_id"
  add_foreign_key "game_scoring_reviews", "schedule_refresh_runs"
  add_foreign_key "game_scoring_reviews", "seasons"
  add_foreign_key "game_scoring_reviews", "users", column: "reviewed_by_id"
  add_foreign_key "game_sync_dates", "seasons"
  add_foreign_key "offseason_input_revisions", "offseason_input_revisions", column: "predecessor_id"
  add_foreign_key "offseason_input_revisions", "seasons"
  add_foreign_key "offseason_readiness_operations", "offseason_readiness_reviews"
  add_foreign_key "offseason_readiness_operations", "seasons"
  add_foreign_key "offseason_readiness_operations", "users", column: "actor_id"
  add_foreign_key "offseason_readiness_reviews", "ratings_config_versions"
  add_foreign_key "offseason_readiness_reviews", "seasons"
  add_foreign_key "offseason_readiness_reviews", "users", column: "reviewer_id"
  add_foreign_key "predictions", "ratings_config_versions"
  add_foreign_key "predictions", "team_rating_snapshots", column: "away_team_snapshot_id"
  add_foreign_key "predictions", "team_rating_snapshots", column: "home_team_snapshot_id"
  add_foreign_key "preseason_priors", "ratings_config_versions"
  add_foreign_key "preseason_priors", "team_seasons"
  add_foreign_key "preseason_publications", "ratings_config_versions"
  add_foreign_key "preseason_publications", "seasons"
  add_foreign_key "preseason_publications", "users", column: "reviewer_id"
  add_foreign_key "recruiting_batches", "offseason_input_revisions", column: "revision_id"
  add_foreign_key "recruiting_batches", "seasons"
  add_foreign_key "recruiting_entries", "recruiting_batches"
  add_foreign_key "recruiting_entries", "teams"
  add_foreign_key "schedule_deferrals", "seasons"
  add_foreign_key "schedule_deferrals", "users", column: "requested_by_id"
  add_foreign_key "schedule_refresh_runs", "schedule_refresh_runs", column: "retry_of_id"
  add_foreign_key "schedule_refresh_runs", "seasons"
  add_foreign_key "schedule_refresh_runs", "users", column: "requested_by_id"
  add_foreign_key "seasons", "ratings_config_versions", column: "preseason_revision_id"
  add_foreign_key "seasons", "ratings_config_versions", column: "selected_preseason_model_id"
  add_foreign_key "team_aliases", "teams"
  add_foreign_key "team_conferences", "conferences"
  add_foreign_key "team_conferences", "seasons", column: "end_season_id"
  add_foreign_key "team_conferences", "seasons", column: "start_season_id"
  add_foreign_key "team_conferences", "teams"
  add_foreign_key "team_external_identities", "teams"
  add_foreign_key "team_games", "team_seasons", column: "opponent_team_season_id"
  add_foreign_key "team_offseason_profiles", "offseason_input_revisions", column: "departure_revision_id"
  add_foreign_key "team_offseason_profiles", "offseason_input_revisions", column: "recruiting_revision_id"
  add_foreign_key "team_rating_snapshots", "ratings_config_versions"
  add_foreign_key "team_rating_snapshots", "seasons"
  add_foreign_key "team_rating_snapshots", "team_seasons"
  add_foreign_key "team_rating_snapshots", "teams"
  add_foreign_key "team_seasons", "preseason_priors"
  add_foreign_key "team_seasons", "ratings_config_versions"
end
