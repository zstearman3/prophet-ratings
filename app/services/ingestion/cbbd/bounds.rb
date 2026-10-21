# frozen_string_literal: true

module Ingestion
  module Cbbd
    # Inclusive Eastern dates are converted once to bounded UTC instants.
    class Bounds
      attr_reader :season

      def initialize(season:, start_date:, end_date:)
        raise ArgumentError, 'season must be an ending-year integer' unless season.to_s.match?(/\A\d{4}\z/)

        @season = season.to_i
        @dates = [Bounds.date(start_date), Bounds.date(end_date)]
        validate_dates
      end

      def start_time
        self.class.midnight(@dates.first)
      end

      def end_time
        self.class.midnight(@dates.last + 1) - Rational(1, 1000)
      end

      def to_h
        { 'season' => season, 'start_date' => @dates.first.iso8601, 'end_date' => @dates.last.iso8601,
          'start_time' => start_time.iso8601(3), 'end_time' => end_time.iso8601(3) }
      end

      def self.date(value)
        string = value.to_s
        raise ArgumentError, 'strict YYYY-MM-DD dates required' unless string.match?(/\A\d{4}-\d{2}-\d{2}\z/)

        Date.iso8601(string)
      end

      def self.midnight(date)
        ActiveSupport::TimeZone['America/New_York'].local(date.year, date.month, date.day).utc
      end

      private

      def validate_dates
        first, last = @dates
        raise ArgumentError, 'reversed date bounds' if last < first
        raise ArgumentError, 'dates outside ending-year season' unless first >= Date.new(season - 1, 7, 1) &&
                                                                       last <= Date.new(season, 6, 30)
      end
    end
  end
end
