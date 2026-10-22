# frozen_string_literal: true

require 'net/http'
require 'time'

module Ingestion
  module Cbbd
    # Bounded read-only requests; the same counter covers endpoints and retries.
    class Client
      # Transport allowlist; game acquisition and replay own their narrower endpoint set.
      ENDPOINTS = %w[/games /games/teams /teams/directory /draft/picks /stats/player/season /stats/team/season].freeze
      TRANSIENT = %w[timeout transport quota].freeze

      def initialize(store:, api_key:, **options)
        @store = store
        @options = { api_key: api_key, transport: HttpTransport.method(:call), sleeper: ->(seconds) { sleep(seconds) },
                     max_requests: 50, retries: 2 }.merge(options)
        @state = { attempts: 0, captures: [] }
        validate_options
      end

      def attempts
        @state.fetch(:attempts)
      end

      def captures
        @state.fetch(:captures)
      end

      def request(filters)
        raise ArgumentError, 'unsupported endpoint' unless ENDPOINTS.include?(filters.fetch('endpoint'))

        request_with_retries(filters)
      end

      def self.excessive_delay?(delay, outcome)
        return false unless delay > 30

        outcome['retry_exhausted'] = true
      end

      def self.failure(error, outcome)
        { status: nil, failure: outcome, error_class: error.class.name }
      end

      private

      def request_with_retries(filters)
        outcome = { 'outcome' => 'request_budget', 'rows' => [] }
        (0..@options.fetch(:retries)).each do |retry_number|
          outcome = budgeted_attempt(filters)
          return outcome unless retry?(outcome, retry_number)
        end
        outcome
      end

      def budgeted_attempt(filters)
        return { 'outcome' => 'request_budget', 'rows' => [] } if attempts >= @options.fetch(:max_requests)

        attempt(filters)
      end

      def validate_options
        raise ArgumentError, 'CBBD_API_KEY is required' if @options.fetch(:api_key).to_s.empty?
        raise ArgumentError, 'invalid request limit' unless @options.fetch(:max_requests).positive?
        raise ArgumentError, 'invalid retry limit' unless @options.fetch(:retries).between?(0, 5)
      end

      def retry?(outcome, retry_number)
        return false unless TRANSIENT.include?(outcome['outcome']) && retry_number < @options.fetch(:retries)

        delay = Response.retry_delay(outcome, retry_number)
        return false if self.class.excessive_delay?(delay, outcome)

        @options.fetch(:sleeper).call(delay)
        true
      end

      def attempt(filters)
        @state[:attempts] += 1
        retain(safe_fetch(filters), filters)
      end

      def safe_fetch(filters)
        fetch(filters)
      rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => error
        Client.failure(error, 'timeout')
      rescue IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError => error
        Client.failure(error, 'transport')
      end

      def fetch(filters)
        uri = URI("https://api.collegebasketballdata.com#{filters.fetch('endpoint')}")
        uri.query = URI.encode_www_form(filters.except('endpoint'))
        @options.fetch(:transport).call(uri, @options.fetch(:api_key))
      end

      def retain(response, filters)
        parsed = Response.new(response, @options.fetch(:api_key), endpoint: filters.fetch('endpoint'))
        reference = @store.capture(body: parsed.body, metadata: parsed.metadata.merge('request' => filters))
        captures << reference
        parsed.outcome.merge('capture' => reference)
      end
    end
  end
end
