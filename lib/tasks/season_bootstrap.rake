# frozen_string_literal: true

namespace :season do
  desc 'Bootstrap a season (default YEAR=2026): create season/team_seasons, sync games, and run initial ratings'
  task bootstrap: :environment do
    year = ENV.fetch('YEAR', '2026').to_i
    abort('YEAR must be a positive integer') unless year.positive?

    sync_games = env_bool('SYNC_GAMES', default: true)
    sync_resume = env_bool('SYNC_RESUME', default: false)
    sync_start_date = parse_date_env('SYNC_START_DATE')
    sync_end_date = parse_date_env('SYNC_END_DATE')
    dedupe_games = env_bool('DEDUPE_GAMES', default: true)
    run_preseason = env_bool('RUN_PRESEASON', default: true)
    run_ratings = env_bool('RUN_RATINGS', default: true)

    season = upsert_season_for_year(year)
    season.set_current! unless season.current?

    created_team_seasons = ensure_team_seasons_for(season)
    ratings_config = RatingsConfigVersion.ensure_current!
    run_preseason_ratings_for(season) if run_preseason

    if sync_games
      SyncFullSeasonGamesJob.perform_now(
        season,
        start_date: sync_start_date,
        end_date: sync_end_date,
        resume: sync_resume
      )
    end

    if dedupe_games
      Rake::Task['games:dedupe'].reenable
      Rake::Task['games:dedupe'].invoke
    end

    if run_ratings
      if season.games.exists?
        GenerateSeasonRatingsJob.perform_now(season.id, run_preseason: false)
      else
        puts 'Skipping ratings backfill: no games found for this season. ' \
             'Run with SYNC_GAMES=true first, then rerun RUN_RATINGS=true.'
      end
    end

    puts "Season bootstrap complete for #{season.name} (year=#{season.year})"
    puts "Season current?: #{season.current?}"
    puts "TeamSeasons created: #{created_team_seasons} (total: #{season.team_seasons.count})"
    puts "Games in season: #{season.games.count}"
    puts "Games sync window override: #{sync_start_date || 'default'}..#{sync_end_date || 'default'}"
    puts "Games sync resume mode: #{sync_resume}"
    puts "Preseason initialized: #{run_preseason}"
    puts "Current ratings config: #{ratings_config.name} (id=#{ratings_config.id})"
  end

  desc 'Sync games for an existing season. Supports SYNC_RESUME=true and SYNC_START_DATE/SYNC_END_DATE.'
  task sync_games: :environment do
    year = ENV.fetch('YEAR', Season.current&.year || Date.current.year).to_i
    abort('YEAR must be a positive integer') unless year.positive?

    season = Season.find_by(year:)
    abort("No season found for year=#{year}. Run season:bootstrap first.") unless season

    sync_resume = env_bool('SYNC_RESUME', default: true)
    sync_start_date = parse_date_env('SYNC_START_DATE')
    sync_end_date = parse_date_env('SYNC_END_DATE')

    SyncFullSeasonGamesJob.perform_now(
      season,
      start_date: sync_start_date,
      end_date: sync_end_date,
      resume: sync_resume
    )

    puts "Games sync complete for #{season.name} (year=#{season.year})"
    puts "Games in season: #{season.games.count}"
    puts "Games sync window override: #{sync_start_date || 'default'}..#{sync_end_date || 'default'}"
    puts "Games sync resume mode: #{sync_resume}"
  end

  def env_bool(key, default:)
    raw = ENV.fetch(key, nil)
    return default if raw.nil?

    ActiveModel::Type::Boolean.new.cast(raw)
  end

  def parse_date_env(key)
    value = ENV.fetch(key, nil)
    return nil if value.blank?

    Date.parse(value)
  rescue ArgumentError
    abort("Invalid #{key} date: #{value.inspect}. Use YYYY-MM-DD.")
  end

  def season_name_for(year)
    "#{year - 1}-#{year.to_s[-2, 2]}"
  end

  def default_season_dates_for(year)
    previous_season = Season.find_by(year: year - 1)
    return [previous_season.start_date.next_year, previous_season.end_date.next_year] if previous_season

    [Date.new(year - 1, 11, 1), Date.new(year, 4, 10)]
  end

  def upsert_season_for_year(year)
    default_start_date, default_end_date = default_season_dates_for(year)
    start_date = parse_date_env('START_DATE') || default_start_date
    end_date = parse_date_env('END_DATE') || default_end_date

    abort('END_DATE must be after START_DATE') if end_date <= start_date

    season_defaults = Rails.application.config_for(:defaults)[:season_defaults] || {}
    average_efficiency = season_defaults[:average_efficiency]
    average_pace = season_defaults[:average_pace]

    season = Season.find_or_initialize_by(year:)
    season.assign_attributes(
      name: season_name_for(year),
      start_date:,
      end_date:,
      average_efficiency: season.average_efficiency || average_efficiency,
      average_pace: season.average_pace || average_pace
    )
    season.save! if season.changed?
    season
  end

  def ensure_team_seasons_for(season)
    existing_team_ids = TeamSeason.where(season_id: season.id).pluck(:team_id).index_with(true)
    created = 0

    Team.find_each do |team|
      next if existing_team_ids.include?(team.id)

      TeamSeason.create!(team:, season:)
      created += 1
    end

    created
  end

  def run_preseason_ratings_for(season)
    ProphetRatings::PreseasonInitializer.new(season).call
  end
end
