# frozen_string_literal: true

module Departures
  # One original body at a time, authenticating metadata and actual bytes rather than supplied digests alone.
  class RetainedSourceReader
    def initialize(attempt_id)
      @attempt_id = Integer(attempt_id)
      @version = DepartureAcquisition.where(id: @attempt_id).pick(Arel.sql("evidence->>'storage_version'"))
      Contract.check!([nil, CaptureStore::VERSION].include?(@version), 'Unsupported departure capture storage version')
    end

    def bytes(source)
      return legacy_bytes(source) unless @version

      observation = CaptureStore.resolve(observation_id(source), source)
      capture = DepartureSourceCapture.all.skip_query_cache!.find(observation.departure_source_capture_id)
      CaptureStore.capture_bytes(capture, source)
    rescue ActiveRecord::RecordNotFound
      raise ArgumentError, 'Missing retained source bytes or observation'
    end

    private

    def observation_id(source)
      reference = DepartureAcquisition.where(id: @attempt_id)
                                      .pick(Arel.sql("jsonb_extract_path_text(evidence, 'observations', ?)", source.fetch('id')))
      Contract.check!(reference.present?, 'Missing retained source bytes or observation')
      Integer(reference)
    end

    def legacy_bytes(source)
      encoded = RetainedEvidence.persisted_source(@attempt_id, source.fetch('id'))
      RetainedEvidence.validate_bytes(source, Base64.strict_decode64(encoded))
    end
  end
end
