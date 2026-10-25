# frozen_string_literal: true

module Ingestion
  # The job holds the run lock throughout this operation; checkpoints share the date transaction.
  class ScheduleRefreshExecution
    def initialize(run)
      @run = run
    end

    def call
      case run.status
      when *ScheduleRefreshRun::TERMINAL then nil
      when 'running' then run.finish('incomplete', 'Worker interrupted. Explicitly retry unfinished dates with a new budget.')
      else execute
      end
    rescue StandardError => error
      record_failure(error)
    end

    private

    attr_reader :run

    def record_failure(error)
      Rails.logger.error { "Schedule refresh failed run_id=#{run.id} exception_class=#{error.class.name}" }
      run.reload.finish('failed', 'Refresh could not run. Check runtime credentials, private capture storage and limits; ' \
                                  'check that the dates match the selected import type.')
    end

    def execute
      validate_pending
      run.update!(status: 'running', started_at: Time.current)
      result = refresh.call
      finalize(result)
    end

    def finalize(result)
      run.update!(report: ScheduleRefreshReport.call(result))
      run.finish(run.pending_dates.empty? ? 'succeeded' : 'incomplete')
    end

    def refresh
      return historical_sync if run.historical?

      FutureScheduleRefresh.new(season: run.season, start_date: run.start_date, end_date: run.end_date,
                                dates: run.requested_dates, provider: run.provider, provider_options:,
                                on_day: method(:checkpoint))
    end

    def historical_sync
      GameSyncRun.new(season: run.season, dates: run.requested_dates.map { |date| Date.iso8601(date) },
                      resume: !run.rescan, provider: run.provider, provider_options:, on_day: method(:checkpoint),
                      allow_partial: run.cbbd?)
    end

    def validate_pending
      if run.historical?
        HistoricalSyncWindow.new(season: run.season, start_date: run.start_date, end_date: run.end_date)
        return
      end

      return if run.requested_dates.all? { |date| Date.iso8601(date) >= Game.current_schedule_date }

      raise ArgumentError, 'Queued dates expired; use historical sync.'
    end

    def provider_options
      run.cbbd? ? { max_requests: run.max_requests, retries: run.retries } : {}
    end

    def checkpoint(day)
      run.checkpoint(ScheduleRefreshReport.call(day))
    end
  end
end
