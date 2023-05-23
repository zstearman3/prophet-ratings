class SyncDailyGamesJob < ApplicationJob
  queue_as :default

  def perform(*args)
    scraper = Scraper::GamesScraper.new(3.months.ago)
    @url_position = 0
    @game_count = scraper.game_count

    while @url_position < @game_count do
      batch_size = max_url_position - @url_position

      data = scraper.to_json_in_batches(@url_position, batch_size)
      Importer::GamesImporter.import(data)

      p "Imported games #{@url_position} to #{max_url_position}"
      @url_position = max_url_position
    end

  end

  private

  def max_url_position
    @url_position + 10 < @game_count ? (@url_position + 10) : @game_count
  end
end
