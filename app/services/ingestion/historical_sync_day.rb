# frozen_string_literal: true

module Ingestion
  # Serialize checkpoint decisions; commit ingestion and completion together for each date.
  class HistoricalSyncDay
    MAX_RETRIES = 5
    BASE_DELAY_SECONDS = 5

    def initialize(season:, date:, resume:)
      @season = season
      @date = date
      @resume = resume
    end

    def call
      result = GoodJob::Job.advisory_lock_key("historical-game-sync:#{season.id}:#{date}") { [sync_day] }
      result ? result.first : { date:, error: 'Another historical sync is running for this date.' }
    end

    private

    attr_reader :season, :date, :resume, :checkpoint

    def sync_day
      @checkpoint = GameSyncDate.find_or_create_by!(season:, schedule_date: date)
      return { date:, status: 'skipped' } if resume && checkpoint.completed?

      ingest_with_retries
    end

    def ingest_with_retries(retries = 0)
      checkpoint.begin_attempt
      ingest_and_complete.merge(date:, status: 'completed', attempts: checkpoint.attempts)
    rescue StandardError => error
      checkpoint.record_failure("#{error.class}: #{error.message}")
      retry_or_report(retries)
    end

    def retry_or_report(retries)
      return { date:, status: 'failed', attempts: checkpoint.attempts, error: checkpoint.last_error } if retries >= MAX_RETRIES

      sleep(BASE_DELAY_SECONDS * (2**retries))
      ingest_with_retries(retries + 1)
    end

    def ingest_and_complete
      GamesIngestionService.with_date_lock(date) { import_transaction }
    end

    def import_transaction
      GameSyncDate.transaction(requires_new: true) do
        result = GamesIngestionService.new(date:, season:).call
        validate_reconciliation(result)
        checkpoint.complete(result)
        result
      end
    end

    def validate_reconciliation(result)
      ambiguous = result.fetch(:games, []).select { |game| game[:outcome] == 'ambiguous' }
      return if ambiguous == []

      raise ArgumentError, "Ambiguous source games: #{ambiguous}"
    end
  end
end
