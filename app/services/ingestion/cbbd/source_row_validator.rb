# frozen_string_literal: true

module Ingestion
  module Cbbd
    # A successful response still must honor the requested identity/time filters.
    class SourceRowValidator
      ID_FIELDS = { '/games' => %w[id homeTeamId awayTeamId], '/games/teams' => %w[gameId teamId opponentId] }.freeze

      def initialize(row, partition)
        @row = row
        @partition = partition
      end

      def call
        return 'invalid_identity' unless valid_identity?
        return 'season_mismatch' unless @row['season'] == @partition['season']

        time_error
      end

      def self.valid_id?(value)
        value.is_a?(Integer) && value.positive?
      end

      private

      def valid_identity?
        ID_FIELDS.fetch(@partition.fetch('endpoint')).all? { |key| self.class.valid_id?(@row[key]) }
      end

      def time_error
        instant = SourceTime.new(@row).instant
        return 'unknown_source_time' unless instant

        'out_of_window' unless instant.between?(Time.iso8601(@partition['startDateRange']), Time.iso8601(@partition['endDateRange']))
      end
    end
  end
end
