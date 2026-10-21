# frozen_string_literal: true

module Ingestion
  module Cbbd
    # File-only adapter; deliberately has no importer or domain model dependency.
    class Adapter
      def initialize(season:, start_date:, end_date:, capture_directory:, **options)
        @bounds = Bounds.new(season: season, start_date: start_date, end_date: end_date)
        @store = CaptureStore.new(capture_directory)
        @limits = { row_cap: options.delete(:row_cap) || 3000, maximum_requests: options.fetch(:max_requests, 50) }
        @client = Client.new(store: @store, **options)
      end

      def call
        retriever = BoundedRetriever.new(client: @client, bounds: @bounds, row_cap: @limits.fetch(:row_cap))
        result = RunNormalizer.new(retriever.call, retriever.ledger).call.merge(run_metadata)
        result['manifest'] = @store.manifest(result)
        result
      end

      def self.replay(manifest:)
        Replay.new(manifest).call
      end

      private

      def run_metadata
        { 'run_id' => SecureRandom.uuid, 'bounds' => @bounds.to_h, 'maximum_requests' => @limits.fetch(:maximum_requests) }
      end
    end
  end
end
