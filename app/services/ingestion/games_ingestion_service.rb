# frozen_string_literal: true

module Ingestion
  class GamesIngestionService
    DEFAULT_BATCH_SIZE = 10

    def initialize(date:, batch_size: DEFAULT_BATCH_SIZE, team: nil, season: nil)
      @date = date
      @batch_size = normalized_batch_size(batch_size)
      @team = team
      @season = season
    end

    def call
      return import_rows(scraper.to_json_for_team(team)) if team

      imported_rows = 0
      games = []
      url_position = 0

      while url_position < game_count
        next_position = [url_position + batch_size, game_count].min
        rows = scraper.to_json_in_batches(url_position, next_position - url_position)
        result = import_rows(rows)
        imported_rows += result[:imported_rows]
        games.concat(result[:games])
        url_position = next_position
      end

      { imported_rows:, games: }
    end

    private

    attr_reader :date, :batch_size, :team, :season

    def import_rows(rows)
      enriched_rows = game_row_enricher.call(rows)
      games = import_games(enriched_rows)
      { imported_rows: imported_count(enriched_rows, games), games: }
    end

    def imported_count(rows, games)
      season ? games.count { |game| game[:outcome] != 'ambiguous' } : rows.size
    end

    def import_games(rows)
      unless season
        Importer::GamesImporter.import(rows)
        return []
      end

      validate_schedule_rows(rows)
      rows.map { |row| Importer::ScheduleRowImporter.new(season:, row:).call }
    end

    def validate_schedule_rows(rows)
      return if rows.all? { |row| Game.schedule_date_for(Game.schedule_time_for(row.fetch(:date))) == date }

      raise ArgumentError, "Source game date does not match requested schedule date #{date}"
    end

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
