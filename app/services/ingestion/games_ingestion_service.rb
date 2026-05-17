# frozen_string_literal: true

module Ingestion
  class GamesIngestionService
    DEFAULT_BATCH_SIZE = 10

    def initialize(date:, batch_size: DEFAULT_BATCH_SIZE)
      @date = date
      @batch_size = normalized_batch_size(batch_size)
    end

    def call
      imported_rows = 0
      url_position = 0

      while url_position < game_count
        next_position = [url_position + batch_size, game_count].min
        rows = scraper.to_json_in_batches(url_position, next_position - url_position)
        enriched_rows = game_row_enricher.call(rows)
        Importer::GamesImporter.import(enriched_rows)
        imported_rows += enriched_rows.size
        url_position = next_position
      end

      { imported_rows: }
    end

    private

    attr_reader :date, :batch_size

    def normalized_batch_size(value)
      value.to_i.positive? ? value.to_i : DEFAULT_BATCH_SIZE
    end

    def scraper
      @scraper ||= Scraper::GamesScraper.new(date)
    end

    def game_count
      @game_count ||= scraper.game_count
    end

    def game_row_enricher
      @game_row_enricher ||= Ingestion::GameRowEnricher.new
    end
  end
end
