# frozen_string_literal: true

module Departures
  # One bounded client and incremental checkpoints retain every response and selected terminal source.
  class CbbdAcquisition
    def initialize(plan:, directory:, **options)
      @directory = directory
      @checkpoint = options.delete(:checkpoint) || ->(_) {}
      @manifest = plan.merge('sources' => CbbdDataset.sources(plan).map { |source| source.merge('failure' => 'Not acquired') },
                             'captures' => [])
      @client = client_for(options)
    end

    def call
      manifest.fetch('sources').dup.each do |source|
        select_source(source, client.request(source.fetch('request')))
      end
      manifest
    end

    def capture(body:, metadata:)
      sha = Digest::SHA256.hexdigest(body)
      Contract.write_bytes(File.join(directory, "#{sha}.json"), body)
      captures = manifest.fetch('captures')
      entry = metadata.merge('id' => "capture-#{captures.size + 1}", 'snapshot_kind' => 'raw_json',
                             'snapshot_sha256' => sha, 'snapshot_location' => "#{sha}.json", 'http_status' => metadata['status'],
                             'observed_at' => metadata.fetch('captured_at'), 'source_as_of_reason' => 'Provider publication time unknown')
      retain_capture(entry, captures)
    end

    def self.failure(outcome)
      state = outcome.fetch('outcome')
      "CBBD #{state}" unless state == 'success'
    end

    private

    def client_for(options)
      plan = manifest
      CbbdDataset.validate_plan(plan)
      key = options.delete(:api_key) { ENV.fetch('CBBD_API_KEY', '') }
      Ingestion::Cbbd::Client.new(store: self, api_key: key, max_requests: plan.fetch('max_requests'),
                                  retries: plan.fetch('retries'), **options)
    end

    def retain_capture(entry, captures)
      @manifest = manifest.merge('captures' => captures + [entry])
      checkpoint.call(manifest)
      entry
    end

    def select_source(source, outcome)
      selected = outcome['capture'] || {}
      replacement = source.merge(selected.except('id'), 'failure' => self.class.failure(outcome), 'selected_capture_id' => selected['id'])
      @manifest = manifest.merge('sources' => BatchAcquisition.replace_source(manifest['sources'], source['id'], replacement))
      checkpoint.call(manifest)
    end

    attr_reader :manifest, :directory, :checkpoint, :client
  end
end
