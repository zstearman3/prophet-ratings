# frozen_string_literal: true

module Ingestion
  # Refresh every requested date, retaining failures and source absences for operator review.
  class FutureScheduleRefresh
    MAX_RETRIES = 3
    BASE_DELAY_SECONDS = 5

    def initialize(season:, start_date:, end_date:, **options)
      @season = season
      @window = [start_date && HistoricalSyncWindow.parse_date(start_date), end_date && HistoricalSyncWindow.parse_date(end_date)]
      validate_window
      @provider_run = GameSyncProvider.new(season:, dates: (self.start_date..self.end_date).to_a,
                                           provider: options[:provider], options: options.fetch(:provider_options, {}))
    end

    def call
      days = (start_date..end_date).map { |date| refresh_day(date) }
      failed, @successful_days = days.partition { |day| day[:error] }
      sync_report(days, failed.pluck(:date))
    end

    def self.complete_coverage?(day)
      day.fetch(:games, []).none? { |report| report.values_at(:scheduled, :game_id) == [true, nil] }
    end

    private

    attr_reader :season, :successful_days, :provider_run

    def sync_report(days, failed_dates)
      { year: season.year, days:, absent_ids: absent_games, failed_dates:, retry_window: GameSyncRun.retry_window(failed_dates),
        complete: failed_dates.empty?, **provider_run.summary }
    end

    def start_date = @window.first
    def end_date = @window.last

    def validate_window
      unless start_date && end_date && start_date <= end_date
        raise ArgumentError, 'Refresh requires an ordered SCHEDULE_START_DATE/SCHEDULE_END_DATE window.'
      end
      return if start_date >= Game.current_schedule_date && start_date >= season.start_date && end_date <= season.end_date

      raise ArgumentError, 'Refresh window must be today or later and entirely inside the target season.'
    end

    def absent_games
      seen_ids = successful_days.flat_map { |day| day.fetch(:games, []) }.filter_map { |game| game[:game_id] }
      absence_dates.flat_map do |date|
        season.games.scheduled.on_schedule_date(date).where.not(id: seen_ids).pluck(:id)
      end
    end

    def absence_dates
      successful_days.select { |day| self.class.complete_coverage?(day) }.pluck(:date)
    end

    def refresh_day(date, attempt: 0)
      GamesIngestionService.with_date_lock(date) do
        refresh_transaction(date).merge(date:)
      end
    rescue StandardError => error
      HistoricalSyncDay.retain_rejection(error)
      retry_or_report(date, error, attempt)
    end

    def refresh_transaction(date)
      Game.transaction(requires_new: true) do
        result = provider_run.call(date)
        HistoricalSyncDay::ReconciliationError.validate(result)

        result
      end
    end

    def retry_or_report(date, error, attempt)
      return HistoricalSyncDay.failure_report(error).merge(date:) if provider_run.cbbd? || attempt >= MAX_RETRIES

      wait_before_retry(attempt)
      refresh_day(date, attempt: attempt + 1)
    end

    def wait_before_retry(attempt)
      Rails.logger.warn { "Schedule refresh retry after attempt #{attempt + 1}/#{MAX_RETRIES}" }
      sleep(BASE_DELAY_SECONDS * (2**attempt))
    end
  end
end
