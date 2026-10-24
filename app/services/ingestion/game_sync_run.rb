# frozen_string_literal: true

module Ingestion
  # Shares one prepared provider across atomic dates, excluding compatible resume checkpoints.
  class GameSyncRun
    def initialize(season:, dates:, **options)
      @season = season
      @dates = dates
      @options = options
      @policy = GameSyncPolicy.new(options[:provider], options.fetch(:provider_options, {}))
    end

    def call
      run = provider_run
      summarize(@dates.map do |date|
        HistoricalSyncDay.new(season: @season, date:, resume:, provider_run: run, on_day: @options[:on_day],
                              allow_partial: @options[:allow_partial]).call
      end).merge(run.summary)
    rescue StandardError => error
      raise provider_failure(error)
    end

    def self.retry_window(dates)
      { start_date: dates.min, end_date: dates.max, resume: true } if dates.any?
    end

    private

    def provider_failure(error)
      return error unless @policy.provider == 'cbbd'
      return error if error.is_a?(GameSyncProvider::Incomplete)

      GameSyncProvider::Incomplete.new(complete: false, scope: @policy.scope, failed_dates: @dates, error_class: error.class.name)
    end

    def summarize(days)
      failures = days.select { |day| day[:error] }.pluck(:date)
      { year: @season.year, days:, failed_dates: failures, complete: failures.empty?, retry_window: retry_window(failures) }
    end

    def resume
      @options.fetch(:resume, true)
    end

    def provider_run
      completed = resume ? GameSyncDate.where(season: @season, status: 'completed', **@policy.scope).pluck(:schedule_date) : []
      GameSyncProvider.new(season: @season, dates: @dates - completed, provider: @policy.provider, options: @policy.options,
                           allow_partial: @options[:allow_partial])
    end

    def retry_window(failures)
      self.class.retry_window(failures)
    end
  end
end
