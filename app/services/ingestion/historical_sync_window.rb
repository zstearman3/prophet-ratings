# frozen_string_literal: true

module Ingestion
  # Reject explicit out-of-range windows before any source request.
  class HistoricalSyncWindow
    def initialize(season:, start_date:, end_date:)
      @season = season
      @start_date = (start_date && HistoricalSyncWindow.parse_date(start_date)) || season.start_date
      @end_date = (end_date && HistoricalSyncWindow.parse_date(end_date)) || [season.end_date, Game.current_schedule_date - 1.day].min
      validate_window
    end

    def dates
      (start_date..end_date).to_a
    end

    def self.parse_date(value)
      case value
      when Date then value.instance_of?(Date) ? value : invalid_date
      when String then /\A\d{4}-\d{2}-\d{2}\z/.match?(value) ? Date.iso8601(value) : invalid_date
      else invalid_date
      end
    end

    def self.invalid_date
      raise ArgumentError, 'Historical sync dates must use YYYY-MM-DD Eastern schedule dates.'
    end

    private

    attr_reader :season, :start_date, :end_date

    def validate_window
      unless start_date >= season.start_date && end_date <= season.end_date && end_date < Game.current_schedule_date
        raise ArgumentError, 'Historical sync window must be entirely inside the target season and no later than yesterday.'
      end
      return if start_date <= end_date

      raise ArgumentError, 'Historical sync requires an ordered, nonempty date window.'
    end
  end
end
