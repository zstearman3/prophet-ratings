# frozen_string_literal: true

class SyncFullSeasonGamesJob < ApplicationJob
  queue_as :default

  MAX_RETRIES = 5
  BASE_DELAY_SECONDS = 5

  def perform(season = Season.current)
    start_date = season.start_date
    end_date = [season.end_date, Date.yesterday].min

    (start_date..end_date).each do |date|
      retry_count = 0
      begin
        import_day(date)
      rescue StandardError => e
        if retry_count < MAX_RETRIES
          delay = BASE_DELAY_SECONDS * (2**retry_count)
          Rails.logger.warn { "Failed to import games for #{d}: #{e.message}. Retrying in #{delay} seconds..." }
          sleep delay
          retry_count += 1
          retry
        else
          Rails.logger.error { "Failed to import games for #{d} after #{MAX_RETRIES} attempts: #{e.message}" }
        end
      end
    end
  end

  private

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
