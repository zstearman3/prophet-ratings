# frozen_string_literal: true

module Ingestion
  module Cbbd
    # Read-only adapter with an injectable private evidence store.
    class Adapter
      def initialize(season:, start_date:, end_date:, capture_directory: nil, **options)
        @bounds = Bounds.new(season: season, start_date: start_date, end_date: end_date)
        @store = options.delete(:store) { CaptureStore.new(capture_directory) }
        @limits = { row_cap: options.delete(:row_cap) || 3000, maximum_requests: options.fetch(:max_requests, 50),
                    retries: options.fetch(:retries, 2) }
        @client = Client.new(store: @store, **options)
      end

      def call
        retriever = BoundedRetriever.new(client: @client, bounds: @bounds, row_cap: @limits.fetch(:row_cap))
        result = normalize(retriever)
        result['manifest'] = @store.manifest(result)
        result
      end

      def self.replay(manifest:)
        Replay.new(manifest).call
      end

      private

      def normalize(retriever)
        rows = retriever.call
        ledger = retriever.ledger
        metadata = run_metadata
        @store.checkpoint(ledger, metadata)
        RunNormalizer.new(rows, ledger).call.merge(metadata)
      end

      def run_metadata
        { 'run_id' => SecureRandom.uuid, 'bounds' => @bounds.to_h, 'maximum_requests' => @limits.fetch(:maximum_requests),
          'retries' => @limits.fetch(:retries) }
      end
    end
  end
end
