# frozen_string_literal: true

module Ingestion
  module Cbbd
    # Reconstructs only originally selected leaves, never reclassifying acquisition.
    class Replay
      def initialize(manifest)
        @manifest = File.expand_path(manifest)
        @saved = JSON.parse(File.read(@manifest))
        @store = CaptureStore.new(File.dirname(@manifest))
      end

      def call
        payloads = verified_payloads
        RunNormalizer.new(selected_rows(payloads), ledger).call.merge(@saved.slice('run_id', 'bounds', 'maximum_requests', 'retries'),
                                                                      'manifest' => @manifest)
      end

      def self.entry(row, index, reference)
        { 'raw' => row, 'provenance' => reference.merge('row_index' => index) }
      end

      private

      def selected_rows(payloads)
        rows = Client::ENDPOINTS.index_with { [] }
        ledger.fetch('selected_captures').each { |id| append_capture(rows, id, payloads.fetch(id)) }
        rows
      end

      def verified_payloads
        ledger.fetch('captures').to_h { |reference| [reference['id'], @store.read(reference)] }
      end

      def ledger
        @saved.fetch('acquisition')
      end

      def append_capture(rows, id, payload)
        reference = ledger.fetch('captures').find { |capture| capture['id'] == id }
        rows.fetch(reference.dig('request', 'endpoint')).concat(accepted_entries(payload, reference))
      end

      def accepted_entries(payload, reference)
        entries = JSON.parse(payload).each_with_index.filter_map do |row, index|
          self.class.entry(row, index, reference) unless SourceRowValidator.new(row, reference.fetch('request')).call
        end
        rejected = ledger.fetch('decisions').pluck('duplicate')
        entries.reject { |entry| rejected.include?(entry['provenance']) }
      end
    end
  end
end
