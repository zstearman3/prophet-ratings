# frozen_string_literal: true

module Ingestion
  # Refresh every requested date, retaining failures and source absences for operator review.
  class FutureScheduleRefresh
    MAX_RETRIES = 3
    BASE_DELAY_SECONDS = 5

    def initialize(season:, start_date:, end_date:)
      @season = season
      @start_date = start_date
      @end_date = end_date
      validate_window
    end

    def call
      days = (start_date..end_date).map { |date| refresh_day(date) }
      failed, @successful_days = days.partition { |day| day[:error] }
      { year: season.year, days:, absent_ids: absent_games, failed_dates: failed.pluck(:date) }
    end

    private

    attr_reader :season, :start_date, :end_date, :successful_days

    def validate_window
      unless start_date && end_date && start_date <= end_date
        raise ArgumentError, 'Refresh requires an ordered SCHEDULE_START_DATE/SCHEDULE_END_DATE window.'
      end
      return if start_date >= Game.current_schedule_date && start_date >= season.start_date && end_date <= season.end_date

      raise ArgumentError, 'Refresh window must be today or later and entirely inside the target season.'
    end

    def absent_games
      seen_ids = successful_days.flat_map { |day| day.fetch(:games, []) }.filter_map { |game| game[:game_id] }
      successful_days.pluck(:date).flat_map do |date|
        season.games.scheduled.on_schedule_date(date).where.not(id: seen_ids).pluck(:id)
      end
    end

    def refresh_day(date, attempt: 0)
      Game.transaction { GamesIngestionService.new(date:, season:).call }.merge(date:)
    rescue StandardError => error
      retry_or_report(date, error, attempt)
    end

    def retry_or_report(date, error, attempt)
      return { date:, error: "#{error.class}: #{error.message}" } if attempt >= MAX_RETRIES

      wait_before_retry(attempt)
      refresh_day(date, attempt: attempt + 1)
    end

    def wait_before_retry(attempt)
      Rails.logger.warn { "Schedule refresh retry after attempt #{attempt + 1}/#{MAX_RETRIES}" }
      sleep(BASE_DELAY_SECONDS * (2**attempt))
    end
  end
end
