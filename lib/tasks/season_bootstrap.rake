# frozen_string_literal: true

namespace :season do
  desc 'Prepare a season and missing TeamSeason rows; requires YEAR'
  task prepare: :environment do
    report_preparation(prepare_target_season)
  rescue ArgumentError, Season::OperationInProgress => e
    abort(e.message)
  end

  desc 'Prepare and review conference alignment without activating or changing ratings; requires YEAR'
  task bootstrap: :environment do
    reject_legacy_bootstrap_operations!
    preparation = prepare_target_season
    review_conferences!(preparation.season) if env_bool('ALIGN_CONFERENCES', default: true)
    report_preparation(preparation)
    puts 'Season bootstrap complete. Initialize/review preseason outputs, then run season:activate explicitly.'
  rescue ArgumentError, Season::OperationInProgress => e
    abort(e.message)
  end

  desc 'Initialize preseason values for a fresh season without activating it; requires YEAR'
  task initialize_preseason: :environment do
    season = target_season!
    Season.with_ratings_lock do
      Season.transaction do
        if season.reload.current?
          abort('Existing season outputs must be preserved. Use an explicitly scoped season:rebuild_ratings for an intentional reset.')
        end
        ProphetRatings::PreseasonInitializer.new(season, ratings_config_version: selected_model_version).call
      end
    end
    puts "Preseason values initialized for year=#{season.year}. Review coverage before activation."
  rescue ArgumentError, Season::OperationInProgress => e
    abort(e.message)
  end

  desc 'Preview a deliberate preseason revision; requires YEAR and MODEL_VERSION; publish with APPLY=true and PREVIEW_KEY'
  task revise_preseason: :environment do
    abort('Select a published new MODEL_VERSION explicitly; preview never changes defaults.') if ENV['MODEL_VERSION'].blank?
    revision = ProphetRatings::PreseasonRevision.new(target_season!, ratings_config_version: selected_model_version)
    report = ENV['APPLY'] == 'true' ? revision.call(preview_key: ENV.fetch('PREVIEW_KEY', nil)) : revision.preview
    puts JSON.pretty_generate(report)
    puts 'Review this version/coverage/evidence and baselines. Publish with APPLY=true and PREVIEW_KEY from this preview.'
  rescue ArgumentError, Season::OperationInProgress => e
    abort(e.message)
  end

  desc 'Report conflicting offseason profiles without choosing or deleting evidence'
  task offseason_profile_duplicates: :environment do
    ids = TeamOffseasonProfile.duplicate_team_season_ids
    puts JSON.pretty_generate(team_season_ids: ids, profile_ids: TeamOffseasonProfile.where(team_season_id: ids).order(:id).pluck(:id))
    abort('Deliberately resolve conflicting evidence before migrating; no rows were changed.') if ids.any?
  end

  desc 'Explicitly activate a prepared season after reviewing conference alignment; requires YEAR'
  task activate: :environment do
    season = target_season!
    review_conferences!(season) if env_bool('ALIGN_CONFERENCES', default: true)
    season.set_current!
    puts "Season activated: year=#{season.year}, preseason_revision=#{season.preseason_revision&.name || 'legacy'}."
    puts 'Scheduled jobs will now select this season.'
  rescue ArgumentError, Season::OperationInProgress => e
    abort(e.message)
  end

  desc 'Sync historical games for an explicit existing YEAR; supports SYNC_START_DATE/SYNC_END_DATE and SYNC_RESUME'
  task sync_games: :environment do
    season = target_season!
    report = SyncFullSeasonGamesJob.new.perform(
      season,
      start_date: ENV.fetch('SYNC_START_DATE', nil),
      end_date: ENV.fetch('SYNC_END_DATE', nil),
      resume: env_bool('SYNC_RESUME', default: true)
    )
    puts JSON.pretty_generate(report)
    puts "Games sync complete for year=#{season.year}. Review unmatched games and venue coverage."
  rescue SyncFullSeasonGamesJob::IncompleteSync => e
    puts JSON.pretty_generate(e.report)
    abort(e.message)
  rescue ArgumentError => e
    abort(e.message)
  end

  desc 'Refresh a bounded future schedule without activating or generating ratings; requires YEAR and SCHEDULE dates'
  task refresh_schedule: :environment do
    result = Ingestion::FutureScheduleRefresh.new(
      season: target_season!, start_date: parse_date_env('SCHEDULE_START_DATE'), end_date: parse_date_env('SCHEDULE_END_DATE')
    ).call
    puts JSON.pretty_generate(result)
    abort('Schedule refresh incomplete; rerun failed_dates with the same explicit window.') if result[:failed_dates].any?
    puts 'Schedule refresh complete. Review ambiguous/unmatched/possible_move_ids and absent_ids; no games were deleted.'
  rescue ArgumentError => e
    abort(e.message)
  end

  desc 'Resume ratings through today without deleting history; requires YEAR'
  task resume_ratings: :environment do
    abort('Use season:initialize_preseason separately.') if env_bool('RUN_PRESEASON', default: false)
    season = target_season!
    run_ratings_job!(ResumeSeasonRatingsJob,
                     season.id,
                     start_date: parse_date_env('RATINGS_START_DATE'),
                     end_date: parse_date_env('RATINGS_END_DATE'))
    puts "Ratings resume finished for year=#{season.year}."
  rescue ArgumentError, Season::OperationInProgress => e
    abort(e.message)
  end

  desc 'Destructively rebuild current-config outputs in an explicit season/date range; requires YEAR and REBUILD=true'
  task rebuild_ratings: :environment do
    abort('Destructive rebuild requires REBUILD=true.') unless ENV['REBUILD'] == 'true'
    season = target_season!
    run_ratings_job!(GenerateSeasonRatingsJob,
                     season.id,
                     rebuild: true,
                     date_range: rebuild_window!,
                     run_preseason: env_bool('RUN_PRESEASON', default: false))
    puts "Ratings rebuild complete for year=#{season.year}."
  rescue ArgumentError, Season::OperationInProgress => e
    abort(e.message)
  end

  def rebuild_window!
    first = parse_date_env('RATINGS_START_DATE')
    last = parse_date_env('RATINGS_END_DATE')
    raise ArgumentError, 'Rebuild requires RATINGS_START_DATE and RATINGS_END_DATE.' unless first && last

    first..last
  end

  def selected_model_version
    ENV['MODEL_VERSION'].present? ? RatingsConfigVersion.find_by!(name: ENV['MODEL_VERSION']) : RatingsConfigVersion.default_version
  end

  def target_year!
    SeasonPreparer.parse_year(ENV.fetch('YEAR', ''))
  end

  # Synchronous operator commands must raise failures, not enqueue an ActiveJob retry and report success.
  def run_ratings_job!(job_class, season_id, **)
    Season.with_ratings_lock { job_class.new.perform(season_id, ratings_config_version_id: selected_model_version.id, **) }
  end

  def target_season!
    year = target_year!
    Season.find_by(year:) || raise(ArgumentError, "No season found for year=#{year}. Run season:prepare first.")
  end

  def prepare_target_season
    SeasonPreparer.new(
      year: target_year!, start_date: parse_date_env('START_DATE'), end_date: parse_date_env('END_DATE')
    ).call
  end

  def report_preparation(preparation)
    puts "Season prepared: #{preparation.season.name} (year=#{preparation.season.year})"
    puts "Season current?: #{preparation.season.current?}"
    puts "TeamSeasons created: #{preparation.team_seasons_created}"
  end

  def reject_legacy_bootstrap_operations!
    %w[SYNC_GAMES DEDUPE_GAMES RUN_PRESEASON RUN_RATINGS RATINGS_RESUME].each do |key|
      next unless env_bool(key, default: false)

      raise ArgumentError, "#{key} is no longer part of bootstrap. Use the separate season tasks documented in docs/offseason.md."
    end
  end

  def review_conferences!(season)
    result = SeasonConferenceAlignment.new(year: season.year).call
    SeasonConferenceAlignmentReporter.new(result:, year: season.year).call
    abort('Resolve suggestions from conference alignment before continuing.') unless result.success?
  rescue SeasonConferenceAlignment::Error, Scraper::ConferenceStandingsScraper::Error => e
    abort("Conference alignment failed for year=#{season.year}: #{e.message}")
  end

  def env_bool(key, default:)
    raw = ENV.fetch(key, nil)
    return default if raw.nil?

    ActiveModel::Type::Boolean.new.cast(raw)
  end

  def parse_date_env(key)
    value = ENV.fetch(key, nil)
    return nil if value.blank?

    Date.iso8601(value)
  rescue ArgumentError
    raise ArgumentError, "Invalid #{key} date: #{value.inspect}. Use YYYY-MM-DD."
  end
end
