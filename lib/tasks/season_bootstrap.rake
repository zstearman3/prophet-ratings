# frozen_string_literal: true

namespace :season do
  desc 'Prepare a future season and TeamSeason rows without making it current'
  task prepare: :environment do
    year = ENV.fetch('YEAR', Date.current.year).to_i
    result = SeasonPreparer.new(
      year:,
      start_date: parse_date_env('START_DATE'),
      end_date: parse_date_env('END_DATE')
    ).call

    puts "Season prepared: #{result.season.name} (year=#{result.season.year})"
    puts "Season current?: #{result.season.current?}"
    puts "TeamSeasons created: #{result.team_seasons_created}"
  rescue ArgumentError => e
    abort(e.message)
  end

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
    ratings_resume = env_bool('RATINGS_RESUME', default: false)
    ratings_start_date = parse_date_env('RATINGS_START_DATE')
    ratings_end_date = parse_date_env('RATINGS_END_DATE')

    preparation = SeasonPreparer.new(
      year:,
      start_date: parse_date_env('START_DATE'),
      end_date: parse_date_env('END_DATE')
    ).call
    season = preparation.season
    season.set_current! unless season.current?

    created_team_seasons = preparation.team_seasons_created
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
        if ratings_resume
          ResumeSeasonRatingsJob.perform_now(
            season.id,
            run_preseason: false,
            start_date: ratings_start_date,
            end_date: ratings_end_date
          )
        else
          GenerateSeasonRatingsJob.perform_now(season.id, run_preseason: false)
        end
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
    puts "Ratings resume mode: #{ratings_resume}"
    puts "Ratings window override: #{ratings_start_date || 'auto'}..#{ratings_end_date || 'season end'}"
    puts "Current ratings config: #{ratings_config.name} (id=#{ratings_config.id})"
  rescue ArgumentError => e
    abort(e.message)
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

  desc 'Resume ratings backfill for an existing season. Supports RATINGS_START_DATE/RATINGS_END_DATE.'
  task resume_ratings: :environment do
    year = ENV.fetch('YEAR', Season.current&.year || Date.current.year).to_i
    abort('YEAR must be a positive integer') unless year.positive?

    season = Season.find_by(year:)
    abort("No season found for year=#{year}. Run season:bootstrap first.") unless season

    run_preseason = env_bool('RUN_PRESEASON', default: false)
    ratings_start_date = parse_date_env('RATINGS_START_DATE')
    ratings_end_date = parse_date_env('RATINGS_END_DATE')

    if season.games.exists?
      ResumeSeasonRatingsJob.perform_now(
        season.id,
        run_preseason:,
        start_date: ratings_start_date,
        end_date: ratings_end_date
      )

      puts "Ratings resume complete for #{season.name} (year=#{season.year})"
      puts "Games in season: #{season.games.count}"
      puts "Preseason initialized: #{run_preseason}"
      puts "Ratings window override: #{ratings_start_date || 'auto'}..#{ratings_end_date || 'season end'}"
    else
      puts 'Skipping ratings resume: no games found for this season. ' \
           'Run season:sync_games first.'
    end
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

  def run_preseason_ratings_for(season)
    ProphetRatings::PreseasonInitializer.new(season).call
  end
end
