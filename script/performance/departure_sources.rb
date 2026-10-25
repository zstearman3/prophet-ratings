# frozen_string_literal: true

module OffseasonPerformance
  # Offline HTML adapter only; it never enables network acquisition or converts historical rows.
  class LegacyDepartureSources
    def initialize(attempt)
      @attempt = attempt
      @sources = attempt.manifest.fetch('sources').index_by { |source| source.fetch('id') }
      @references = {}
    end

    def call
      normalize
      @attempt.update!(evidence: { 'storage_version' => Departures::CaptureStore::VERSION, 'observations' => @references })
      # Discard save mutation snapshots before annual normalization deserializes its own metadata header.
      @attempt.reload
    end

    def normalize
      content = Content.new(scale: Integer(ENV.fetch('BENCHMARK_SCALE')))
      content.each_source { |source, bytes| retain(source.fetch('id'), bytes) }
    end

    def retain(id, bytes)
      source = @sources.fetch(id)
      Departures::RetainedEvidence.validate_bytes(source, bytes)
      capture(source, bytes)
      Departures::SourceNormalizer.new(source, bytes, @attempt.plan).call
    end

    def capture(source, bytes)
      Dir.mktmpdir('departure-benchmark-') do |directory|
        Departures::Contract.write_bytes(File.join(directory, source.fetch('snapshot_location')), bytes)
        evidence = Departures::CaptureStore.new(@attempt).retain({ 'sources' => [source] }, directory)
        @references.merge!(evidence.fetch('observations'))
      end
    end
  end

  # Uses the actual departure acquisition and checkpoint services against strictly synthetic responses.
  class CbbdDepartureSources
    def initialize(attempt)
      @attempt = attempt
    end

    def call
      Dir.mktmpdir('departure-benchmark-cbbd-') { |directory| acquire(directory) }
    end

    def acquire(directory)
      checkpoint = ->(manifest) { checkpoint(manifest, directory) }
      transport = ->(uri, _key) { DepartureCbbdContent.new.response(uri) }
      Departures::CbbdAcquisition.new(plan: @attempt.plan, directory:, checkpoint:, transport:,
                                      api_key: 'synthetic-offline-only', metadata_only: true).call
    end

    def checkpoint(manifest, directory)
      @attempt.with_lock do
        @attempt.update!(manifest:, evidence: Departures::CaptureStore.new(@attempt).retain(manifest, directory))
      end
    end
  end
end
