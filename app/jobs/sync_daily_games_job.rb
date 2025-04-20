# frozen_string_literal: true

class SyncDailyGamesJob < ApplicationJob
  queue_as :default

  def perform(date = Date.yesterday)
    scraper = Scraper::GamesScraper.new(date)
    url_position = 0
    game_count = scraper.game_count

    while url_position < game_count
      next_position = [url_position + 10, game_count].min

      data = scraper.to_json_in_batches(url_position, next_position - url_position)
      Importer::GamesImporter.import(data)

      Rails.logger.debug { "Imported games #{url_position} to #{next_position} for #{date}" }

      url_position = next_position
    end
  end
end