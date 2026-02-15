# frozen_string_literal: true

class SyncFullSeasonGamesJob < ApplicationJob
  queue_as :default

  MAX_RETRIES = 5
  BASE_DELAY_SECONDS = 5

  def perform(season = Season.current, start_date: nil, end_date: nil, resume: false)
    season = resolve_season(season)
    date_range = sync_date_range(season, start_date:, end_date:, resume:)
    return if date_range.nil?

    date_range.each do |date|
      retry_count = 0
      begin
        import_day(date)
      rescue StandardError => e
        if retry_count < MAX_RETRIES
          delay = BASE_DELAY_SECONDS * (2**retry_count)
          Rails.logger.warn { "Failed to import games for #{date}: #{e.message}. Retrying in #{delay} seconds..." }
          sleep delay
          retry_count += 1
          retry
        else
          Rails.logger.error { "Failed to import games for #{date} after #{MAX_RETRIES} attempts: #{e.message}" }
        end
      end
    end
  end

  private

  def resolve_season(season)
    return season if season.is_a?(Season)

    Season.find(season)
  end

  def sync_date_range(season, start_date:, end_date:, resume:)
    sync_end_date = [coerce_date(end_date) || season.end_date, Date.yesterday].min
    sync_start_date = coerce_date(start_date) || (resume ? resume_start_date(season) : season.start_date)
    sync_start_date = [sync_start_date, season.start_date].max

    if sync_start_date > sync_end_date
      Rails.logger.info do
        "Skipping season sync for #{season.year}: computed empty range " \
          "(start=#{sync_start_date}, end=#{sync_end_date})"
      end
      return nil
    end

    sync_start_date..sync_end_date
  end

  def resume_start_date(season)
    latest_imported = season.games.maximum(:start_time)&.to_date
    latest_imported || season.start_date
  end

  def coerce_date(value)
    return value if value.is_a?(Date)
    return value.to_date if value.respond_to?(:to_date)
    return if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def import_day(date)
    Rails.logger.info { "Starting game scrape for #{date}" }

    scraper = Scraper::GamesScraper.new(date)
    @url_position = 0
    @game_count = scraper.game_count

    while @url_position < @game_count
      batch_size = max_url_position - @url_position

      data = scraper.to_json_in_batches(@url_position, batch_size)
      Importer::GamesImporter.import(data)

      Rails.logger.info { "Imported games #{@url_position} to #{max_url_position} of #{@game_count} for #{date}" }
      @url_position = max_url_position
    end
  end

  def max_url_position
    @url_position + 10 < @game_count ? (@url_position + 10) : @game_count
  end
end
