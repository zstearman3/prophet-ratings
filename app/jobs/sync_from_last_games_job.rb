# frozen_string_literal: true

class SyncFromLastGamesJob < ApplicationJob
  queue_as :default

  def perform(*_args)
    (start_date.to_date..end_date.to_date).each do |d|
      scraper = Scraper::GamesScraper.new(d)
      @url_position = 0
      @game_count = scraper.game_count

      while @url_position < @game_count
        batch_size = max_url_position - @url_position

        data = scraper.to_json_in_batches(@url_position, batch_size)
        Importer::GamesImporter.import(data)

        Rails.logger.debug { "Imported games #{@url_position} to #{max_url_position} of #{@game_count} for #{d}" }
        @url_position = max_url_position
      end
    end
  end

  private

  def start_date
    [Game.order(start_time: :desc).first.start_time, Season.last.start_date].max
  end

  def end_date
    [Season.last.end_date, Date.yesterday].min
  end

  def max_url_position
    @url_position + 10 < @game_count ? (@url_position + 10) : @game_count
  end
end
