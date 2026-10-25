# frozen_string_literal: true

module Departures
  # Checkpoints append bytes and provenance, never base64 copies of the annual payload.
  class CaptureStore
    VERSION = 'departure-captures-v1'

    def initialize(attempt)
      @attempt = attempt
      @directory = nil
      @references = {}
    end

    def retain(manifest, directory)
      @directory = directory
      @references = initial_references
      self.class.ordered_sources(manifest).each { |source| append_observation(source) }
      { 'storage_version' => VERSION, 'observations' => @references }
    end

    def self.ordered_sources(manifest)
      manifest.fetch('captures', []) + manifest.fetch('sources')
    end

    def initial_references
      evidence = attempt.evidence.presence || { 'storage_version' => VERSION, 'observations' => {} }
      self.class.validate_version(evidence)
      evidence.fetch('observations').dup
    end

    def append_observation(source)
      id = source.fetch('id')
      return if @references.key?(id) || !source['snapshot_location']

      @references[id] = observation(source).id
    end

    def observation(source)
      selected = source['selected_capture_id']
      return CaptureStore.resolve(@references.fetch(selected), source) if selected

      DepartureCaptureObservation.create!(observation_attributes(source))
    end

    def observation_attributes(source)
      bytes = RetainedEvidence.validate_bytes(source, File.binread(File.join(@directory, source.fetch('snapshot_location'))))
      { departure_source_capture: CaptureStore.capture(bytes), departure_acquisition: attempt, source_id: source.fetch('id'),
        metadata: source, extraction_version: attempt.plan.fetch('extraction_version', Contract::EXTRACTION) }
    end

    def bytes(id, source)
      reference = attempt.evidence.fetch('observations').fetch(id)
      observation = DepartureCaptureObservation.find(reference)
      CaptureStore.validate_metadata(source, observation.metadata)
      CaptureStore.capture_bytes(DepartureSourceCapture.all.skip_query_cache!.find(observation.departure_source_capture_id), source)
    rescue ActiveRecord::RecordNotFound, KeyError
      raise ArgumentError, 'Missing retained source bytes or observation'
    end

    def self.capture(bytes)
      capture = capture_record(bytes)
      Contract.check!(capture.byte_size == bytes.bytesize && capture.body == bytes.b, 'Capture content identity collision')
      capture
    end

    def self.capture_record(bytes)
      DepartureSourceCapture.all.skip_query_cache!.create_or_find_by!(sha256: Digest::SHA256.hexdigest(bytes)) do |row|
        row.assign_attributes(body: bytes, byte_size: bytes.bytesize)
      end
    end

    def self.capture_bytes(capture, source)
      bytes = capture.body
      Contract.check!(capture.byte_size == bytes.bytesize && capture.sha256 == source.fetch('snapshot_sha256'), 'Capture identity mismatch')
      RetainedEvidence.validate_bytes(source, bytes)
    end

    def self.validate_version(evidence)
      Contract.check!(evidence['storage_version'] == VERSION, 'Unsupported departure capture storage version')
    end

    private

    attr_reader :attempt

    public_class_method def self.resolve(id, metadata)
      observation = DepartureCaptureObservation.find(id)
      validate_metadata(metadata, observation.metadata)
      observation
    end

    public_class_method def self.validate_metadata(source, original)
      fields = %w[request snapshot_kind snapshot_location snapshot_sha256 http_status captured_at observed_at sanitized]
      Contract.check!(source.slice(*fields) == original.slice(*fields), 'Retained observation metadata mismatch')
    end
  end
end
