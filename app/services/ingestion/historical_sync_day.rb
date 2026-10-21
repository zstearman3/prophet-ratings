# frozen_string_literal: true

module Ingestion
  # Serialize checkpoint decisions; commit ingestion and completion together for each date.
  class HistoricalSyncDay
    # Carries rejected evidence out of the date savepoint without preserving rolled-back foreign keys.
    class ReconciliationError < StandardError
      attr_reader :rejections, :report

      def initialize(result)
        reports = result.fetch(:games).select { |game| GameSyncProvider.held?(game) }
        @report = ReconciliationError.rollback_report(result)
        @rejections = ReconciliationError.rejected_attributes(reports)
        super("Rejected source games: #{reports}")
      end

      def self.rollback_report(result)
        result.merge(complete: false, rolled_back: true, attempted_rows: result[:imported_rows], imported_rows: 0,
                     counts: result.fetch(:counts, {}).merge(accepted: 0),
                     games: result.fetch(:games).map do |game|
                       game.merge(accepted: false, applied: false, game_id: nil, observation_id: nil)
                     end)
      end

      def self.rejected_attributes(reports)
        ::GameObservation.where(id: reports.map { |report| report[:observation_id] }).map do |record|
          record.attributes.except('id', 'created_at', 'updated_at').merge(
            'accepted' => false, 'game_id' => nil, 'reason' => "date_rolled_back: #{record.reason}"
          )
        end
      end

      def self.validate(result)
        rejected = result.fetch(:games, []).select { |game| GameSyncProvider.held?(game) }
        raise self, result if rejected.any?
      end

      def retain
        rejections.each { |attributes| ::GameObservation.create!(attributes) }
      end
    end

    MAX_RETRIES = 5
    BASE_DELAY_SECONDS = 5

    def initialize(season:, date:, resume:, provider_run: nil)
      @season = season
      @date = date
      @options = { resume:, provider_run: }
    end

    def call
      result = GoodJob::Job.advisory_lock_key("historical-game-sync:#{season.id}:#{date}") { [sync_day] }
      result ? result.first : { date:, error: 'Another historical sync is running for this date.' }
    end

    def self.retain_rejection(error)
      error.retain if error.is_a?(ReconciliationError)
    end

    def self.failure_report(error)
      report = error.is_a?(ReconciliationError) ? error.report : {}
      report.merge(error: "#{error.class}: #{error.message}")
    end

    private

    attr_reader :season, :date, :checkpoint

    def provider_run
      @options[:provider_run] ||= GameSyncProvider.new(season:, dates: [date])
    end

    def sync_day
      @checkpoint = GameSyncDate.find_or_create_by!(season:, schedule_date: date, **provider_run.scope)
      return { date:, status: 'skipped' } if @options[:resume] && checkpoint.completed?

      ingest_with_retries
    end

    def ingest_with_retries(retries = 0)
      checkpoint.begin_attempt
      ingest_and_complete.merge(date:, status: 'completed', attempts: checkpoint.attempts)
    rescue StandardError => error
      record_failure(error)
      retry_or_report(retries)
    end

    def retry_or_report(retries)
      if provider_run.cbbd? || retries >= MAX_RETRIES
        return @options.fetch(:failure_report, {}).merge(date:, status: 'failed', attempts: checkpoint.attempts,
                                                         error: checkpoint.last_error)
      end

      sleep(BASE_DELAY_SECONDS * (2**retries))
      ingest_with_retries(retries + 1)
    end

    def ingest_and_complete
      GamesIngestionService.with_date_lock(date) { import_transaction }
    end

    def import_transaction
      GameSyncDate.transaction(requires_new: true) do
        result = provider_run.call(date)
        ReconciliationError.validate(result)
        checkpoint.complete(result)
        result
      end
    end

    def record_failure(error)
      day_class = self.class
      day_class.retain_rejection(error)
      checkpoint.record_failure("#{error.class}: #{error.message}")
      @options[:failure_report] = day_class.failure_report(error)
    end
  end
end
