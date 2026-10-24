# frozen_string_literal: true

module Ingestion
  # Serialize checkpoint decisions; commit ingestion and completion together for each date.
  class HistoricalSyncDay
    # Carries rejected evidence out of the date savepoint without preserving rolled-back foreign keys.
    class ReconciliationError < StandardError
      attr_reader :rejections, :report, :retained_observation_ids

      def initialize(result, rollback_reason: 'date_rolled_back')
        reports = result.fetch(:games).select { |game| GameSyncProvider.held?(game) }
        @report = ReconciliationError.rollback_report(result)
        @rejections = ReconciliationError.rejected_attributes(reports, rollback_reason)
        super("Rejected source games: #{reports}")
      end

      def self.rollback_report(result)
        result.merge(complete: false, rolled_back: true, attempted_rows: result[:imported_rows], imported_rows: 0,
                     counts: result.fetch(:counts, {}).merge(accepted: 0),
                     games: result.fetch(:games).map do |game|
                       game.merge(accepted: false, applied: false, game_id: nil, observation_id: nil)
                     end)
      end

      def self.rejected_attributes(reports, rollback_reason)
        ::GameObservation.where(id: reports.map { |report| report[:observation_id] }).map do |record|
          record.attributes.except('id', 'created_at', 'updated_at').merge(
            'accepted' => false, 'game_id' => nil, 'reason' => "#{rollback_reason}: #{record.reason}"
          )
        end
      end

      def self.validate(result)
        rejected = result.fetch(:games, []).select { |game| GameSyncProvider.held?(game) }
        raise self, result if rejected.any?
      end

      def retain
        @retained_observation_ids = rejections.map { |attributes| ::GameObservation.create!(attributes).id }
      end

      def retained_game_report
        retain
        report.fetch(:games).sole.merge(observation_id: retained_observation_ids.sole)
      end
    end

    MAX_RETRIES = 5
    BASE_DELAY_SECONDS = 5

    def initialize(season:, date:, resume:, **options)
      @season = season
      @date = date
      @options = options.merge(resume:)
    end

    def call
      result = GoodJob::Job.advisory_lock_key("historical-game-sync:#{season.id}:#{date}") { [sync_day] }
      result ? result.first : { date:, error: 'Another historical sync is running for this date.' }
    end

    def self.retain_rejection(error)
      error.retain if error.is_a?(ReconciliationError)
    end

    def self.failure_report(error)
      report = error.is_a?(ReconciliationError) ? error.report.merge(rejection_observation_ids: error.retained_observation_ids) : {}
      report.merge(error: "#{error.class}: #{error.message}")
    end

    def self.rejection_ids(result)
      result.fetch(:games).select { |game| GameSyncProvider.held?(game) }.pluck(:observation_id).compact
    end

    private

    attr_reader :season, :date, :checkpoint

    def provider_run
      @options[:provider_run] ||= GameSyncProvider.new(season:, dates: [date])
    end

    def sync_day
      @checkpoint = GameSyncDate.find_or_create_by!(season:, schedule_date: date, **provider_run.scope)
      return notify({ date:, status: 'skipped' }) if @options[:resume] && checkpoint.completed?

      ingest_with_retries
    end

    def ingest_with_retries(retries = 0)
      checkpoint.begin_attempt
      ingest_and_complete
    rescue StandardError => error
      record_failure(error)
      retry_or_report(retries)
    end

    def retry_or_report(retries)
      if provider_run.cbbd? || retries >= MAX_RETRIES
        return notify(@options.fetch(:failure_report, {}).merge(date:, status: 'failed', attempts: checkpoint.attempts,
                                                                error: checkpoint.last_error))
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
        outcome = save_result(result)
        notify(outcome.merge(date:, attempts: checkpoint.attempts))
      end
    end

    def save_result(result)
      return save_partial_result(result) if @options[:allow_partial] && provider_run.cbbd? && !result[:complete]

      ReconciliationError.validate(result)
      checkpoint.complete(result)
      result.merge(status: 'completed')
    end

    def save_partial_result(result)
      message = 'Some source games need review; see the committed row count.'
      checkpoint.update!(status: 'failed', imported_rows: result.fetch(:imported_rows), completed_at: nil, last_error: message)
      result.merge(status: 'failed', error: message, rejection_observation_ids: self.class.rejection_ids(result))
    end

    def notify(result)
      @options[:on_day]&.call(result)
      result
    end

    def record_failure(error)
      day_class = self.class
      day_class.retain_rejection(error)
      checkpoint.record_failure("#{error.class}: #{error.message}")
      @options[:failure_report] = day_class.failure_report(error)
    end
  end
end
