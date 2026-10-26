# frozen_string_literal: true

module Recruiting
  # Checkpoints every bounded CBBD attempt, including failures, before normalizing the selected response.
  class CbbdAcquisition
    def initialize(batch, **options)
      @batch = batch
      @captures = []
      @year = batch.source_year
      @client = client_for(options)
    end

    def call(&)
      outcome = @client.request('endpoint' => '/recruiting/teams', 'year' => @year).fetch('outcome')
      return retain(outcome, []) unless outcome == 'success'

      retain('ok', CbbdExtract.normalize(selected_body, @year), &)
    rescue ArgumentError, JSON::ParserError => error
      retain('invalid_source', [], error.message)
    end

    def capture(body:, metadata:)
      index = @captures.size
      @captures << { 'body_base64' => Base64.strict_encode64(body), 'sha256' => Digest::SHA256.hexdigest(body), 'metadata' => metadata }
      @batch.update!(snapshot_bytes: snapshot, page_count: index + 1)
      index
    end

    private

    def client_for(options)
      key = options.delete(:api_key) { ENV.fetch('CBBD_API_KEY', '') }
      Ingestion::Cbbd::Client.new(store: self, api_key: key, max_requests: 3, retries: 2, **options)
    end

    def selected_body
      Base64.strict_decode64(@captures.last.fetch('body_base64'))
    end

    def snapshot
      JSON.generate('captures' => @captures, 'selected_capture' => @captures.size - 1)
    end

    def document(status, rows)
      now = Time.current.iso8601(6)
      year = @batch.source_year
      { 'provider' => CbbdExtract::PROVIDER, 'extraction_version' => CbbdExtract::VERSION,
        'category' => Extract::CATEGORY, 'conference_scope' => 'all', 'source_year' => year,
        'target_season' => @batch.season.year, 'source_url' => CbbdExtract.source_url(year),
        'source_status' => status, 'observed_at' => now, 'retrieved_at' => now, 'captured_at' => now,
        'source_as_of' => nil, 'source_as_of_reason' => 'Provider publication time unavailable; freshness not independently verified',
        'snapshot_kind' => 'raw_json_bundle', 'snapshot_location' => 'RecruitingBatch.snapshot_bytes (exact response bytes)',
        'coverage_note' => "#{rows.size} team rows; annual completeness and freshness not independently verified; omitted teams unknown",
        'rows' => rows }
    end

    def retain(status, rows, failure = "CBBD #{status}", &)
      source = document(status, rows)
      bytes = JSON.generate(source)
      state = status == 'ok' ? success_attributes(bytes) : { status: 'failed', failure_message: failure, dataset_revision: nil }
      persist(state.merge(source_status: status, extract_bytes: bytes, snapshot_bytes: snapshot,
                          coverage_note: source.fetch('coverage_note'), page_count: @captures.size), &)
    end

    def persist(attributes)
      @batch.with_lock do
        @batch.update!(attributes)
        yield if block_given?
      end
    end

    def success_attributes(bytes)
      { status: 'ready', failure_message: nil, dataset_revision: Dataset.new(bytes, snapshot).manifest.fetch('dataset_revision') }
    end
  end
end
