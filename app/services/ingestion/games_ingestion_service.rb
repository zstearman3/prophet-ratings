# frozen_string_literal: true

module Ingestion
  class GamesIngestionService
    DEFAULT_BATCH_SIZE = 10

    # A competing date writer must finish before another import can start.
    class ImportInProgress < StandardError; end

    def initialize(date:, batch_size: DEFAULT_BATCH_SIZE, team: nil, season: nil)
      @date = date
      @batch_size = normalized_batch_size(batch_size)
      @team = team
      @season = season
    end

    def call
      GamesIngestionService.with_date_lock(date) { ingest }
    end

    # Session locks are reentrant so callers can keep this lock through their date transaction's commit.
    def self.with_date_lock(date)
      result = GoodJob::Job.advisory_lock_key("games-ingestion:#{date}") { [yield] }
      raise ImportInProgress, "Another game import is running for #{date}." unless result

      result.first
    end

    private

    attr_reader :date, :batch_size, :team, :season

    def ingest
      team ? import_rows(scraper.to_json_for_team(team)) : import_date
    end

    def import_date
      results = (0...game_count).step(batch_size).map { |offset| import_batch(offset) }
      { imported_rows: results.sum { |result| result[:imported_rows] }, games: results.flat_map { |result| result[:games] } }
    end

    def import_batch(offset)
      rows = scraper.to_json_in_batches(offset, [batch_size, game_count - offset].min)
      import_rows(rows)
    end

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
