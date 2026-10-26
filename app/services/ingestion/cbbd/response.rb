# frozen_string_literal: true

module Ingestion
  module Cbbd
    # Only response bytes and allowlisted metadata enter durable evidence.
    class Response
      HEADERS = %w[retry-after x-ratelimit-limit x-ratelimit-remaining x-ratelimit-reset].freeze
      STATUS_FAILURES = { 401 => 'authentication', 403 => 'authentication', 429 => 'quota' }.freeze

      def initialize(response, key, **options)
        @options = options
        @response = response
        @key = key
        @status = response[:status]
      end

      def body
        sanitize(@response.fetch(:body, '').to_s)
      end

      def headers
        @response.fetch(:headers, {}).transform_keys(&:downcase).slice(*HEADERS).transform_values { |value| sanitize(value.to_s) }
      end

      def metadata
        { 'version' => 1, 'captured_at' => Time.now.utc.iso8601(6), 'status' => @response[:status],
          'headers' => headers, 'error_class' => @response[:error_class],
          'outcome' => outcome['outcome'], 'sanitized' => body != @response[:body].to_s }
      end

      def outcome
        failure = @response[:failure] || status_failure
        return { 'outcome' => failure, 'rows' => [], 'headers' => headers } if failure

        parse.merge('headers' => headers)
      end

      def self.retry_delay(outcome, retry_number)
        fallback = 2**retry_number
        value = outcome.fetch('headers', {})['retry-after']
        return fallback unless value

        parse_retry_delay(value)
      rescue ArgumentError
        fallback
      end

      def self.parse_retry_delay(value)
        return value.to_i if value.match?(/\A\d+\z/)

        [Time.httpdate(value) - Time.now.utc, 0].max
      end

      def self.valid_rows?(rows)
        rows.is_a?(Array) && rows.all?(Hash)
      end

      private

      def sanitize(value)
        value.b.gsub(@key.b, '[REDACTED]')
      end

      def status_failure
        failure = STATUS_FAILURES[@status]
        return failure if failure
        return 'transport' if @status >= 500

        'http' unless @status == 200
      end

      def valid_envelope?(rows)
        @options[:endpoint] == '/teams/directory' ? rows.is_a?(Hash) : self.class.valid_rows?(rows)
      end

      def parse
        return (@bounded_outcome ||= { 'outcome' => Departures::JsonRows.outcome(body), 'rows' => [] }) if @options[:metadata_only]

        rows = JSON.parse(body)
        return { 'outcome' => 'malformed_envelope', 'rows' => [] } unless valid_envelope?(rows)

        { 'outcome' => 'success', 'rows' => rows }
      rescue JSON::ParserError
        { 'outcome' => 'malformed_json', 'rows' => [] }
      end
    end
  end
end
