# frozen_string_literal: true

module Ingestion
  module Cbbd
    # Retains a TBD calendar date without fabricating an exact tip time.
    class SourceTime
      def initialize(row)
        @row = row
      end

      def instant
        self.class.parse(@row['startDate'])
      end

      def self.parse(raw)
        return unless raw.is_a?(String) && raw.match?(/T.*(?:Z|[+-]\d{2}:\d{2})\z/)

        Time.iso8601(raw).utc
      rescue ArgumentError
        nil
      end

      def to_h
        { 'schedule_date' => schedule_date, 'start_time' => exact_time, 'time_precision' => precision,
          'time_reason' => reason, 'raw_start_time' => @row['startDate'] }
      end

      private

      def tbd?
        @row['startTimeTbd'] == true
      end

      def schedule_date
        instant&.in_time_zone('America/New_York')&.strftime('%Y-%m-%d')
      end

      def exact_time
        instant&.iso8601(3) if precision == 'instant'
      end

      def precision
        return 'unknown' unless instant

        tbd? ? 'date' : 'instant'
      end

      def reason
        return 'invalid_or_missing_timestamp' unless instant

        'source_tbd' if tbd?
      end
    end
  end
end
