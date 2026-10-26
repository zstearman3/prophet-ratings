# frozen_string_literal: true

module Departures
  # All retry bytes are verified, while only selected successful sources become normalized evidence.
  class StoredSources
    def initialize(attempt)
      @attempt = attempt
    end

    def call
      validate_manifest
      verify_ledger_bytes
      manifest.fetch('sources').each_with_object({}) { |source, parsed| normalize(source, parsed) }
    end

    private

    def retained
      RetainedEvidence.new(@attempt)
    end

    def verify_ledger_bytes
      manifest.fetch('captures', []).each { |source| retained.bytes(source.fetch('id')) }
    end

    def normalize(source, parsed)
      id = source.fetch('id')
      bytes = retained.bytes(id) if source.key?('snapshot_location')
      parsed[id] = SourceNormalizer.new(source, bytes, manifest).call if self.class.successful?(source)
    end

    public_class_method def self.successful?(source)
      source['failure'].blank?
    end

    def manifest
      @attempt.manifest
    end

    def validate_manifest
      return unless manifest['provider'] == 'cbbd'

      CapturePreparation.validate_acquisition_plan(@attempt.plan)
      expected = CbbdDataset.sources(manifest)
      StoredSources.validate_requests(manifest.fetch('sources'), expected)
      StoredSources.validate_ledger(manifest, expected.pluck('request'))
    end

    public_class_method def self.validate_requests(sources, expected)
      actual = sources.map { |source| source.slice('id', 'type', 'url', 'request') }
      Contract.check!(actual == expected, 'Invalid retained source requests')
    end

    public_class_method def self.validate_capture(capture, requests)
      Contract.check!(capture['snapshot_kind'] == 'raw_json' && requests.include?(capture['request']),
                      'Invalid capture ledger request/kind')
    end

    public_class_method def self.validate_selected(manifest, captures)
      CbbdDataset.validate_selected(manifest.fetch('sources'), captures.index_by { |capture| capture.fetch('id') })
    end

    public_class_method def self.validate_ledger(manifest, requests)
      captures = manifest.fetch('captures')
      CbbdDataset.validate_capture_count(captures, manifest.fetch('max_requests'))
      captures.each { |capture| validate_capture(capture, requests) }
      validate_selected(manifest, captures)
    end
  end
end
