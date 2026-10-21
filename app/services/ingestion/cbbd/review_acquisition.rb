# frozen_string_literal: true

module Ingestion
  module Cbbd
    # A job has one finite budget; interrupted work is retained rather than refetched.
    class ReviewAcquisition
      # Safe category: no credential or raw exception text is persisted.
      class MissingApiKey < StandardError; end

      def initialize(run, **options)
        @run = run
        @options = options
      end

      def call
        return unless pending?
        return @run.update!(status: 'failed', failure: 'Acquisition interrupted; start a new bounded run') if @run.status == 'running'

        execute
      rescue StandardError => error
        retain_failure(error)
      end

      def self.failure_message(error)
        return 'CBBD_API_KEY is required on the worker; configure credentials and start a new run' if error.is_a?(MissingApiKey)

        "Acquisition failed (#{error.class.name}); inspect retained evidence"
      end

      private

      def pending?
        %w[queued running].include?(@run.status)
      end

      def execute
        start
        finish(acquire)
      end

      def acquire
        key = @options.fetch(:api_key) { ENV.fetch('CBBD_API_KEY', '') }
        raise MissingApiKey if key.to_s.empty?

        Adapter.new(season: @run.season.year, start_date: @run.start_date.to_s, end_date: @run.end_date.to_s,
                    store: DatabaseCaptureStore.new(@run), max_requests: @run.maximum_requests, retries: @run.retries,
                    api_key: key, **@options.except(:api_key)).call
      end

      def retain_failure(error)
        @run.update!(status: 'failed', failure: self.class.failure_message(error))
      end

      def finish(result)
        complete = result['complete']
        @run.update!(status: complete ? 'completed' : 'failed',
                     failure: complete ? nil : 'Incomplete acquisition or normalization; inspect retained evidence')
      end

      def start
        @run.update!(status: 'running')
      end
    end
  end
end
