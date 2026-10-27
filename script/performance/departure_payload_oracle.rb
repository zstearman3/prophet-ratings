# frozen_string_literal: true

module OffseasonPerformance
  # Verification only, after worker terminal evidence: never supplies facts or expected hashes to application work.
  module DeparturePayloadOracle
    ALLOWED_REVIEW_FIELDS = %w[revision_id reviewed_by reviewed_at].freeze
    METADATA_DIFFERENCES = %w[review.revision_id review.reviewed_by review.reviewed_at review_hash report.reviewed_revision].freeze

    def self.call(original_id, operation, approval)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      before_bytes = DepartureValidationDriver.database_bytes
      expected = expected_payload(original_id, approval)
      verify_expected_payload(operation.offseason_input_revision_id, expected)
      { 'exact_original_payload' => true, 'canonical_input_hash' => true, 'driver_memory' => Telemetry.memory,
        'elapsed_seconds' => Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
        'database_bytes_delta' => DepartureValidationDriver.database_bytes - before_bytes,
        'metadata_differences' => METADATA_DIFFERENCES }
    end

    def self.expected_payload(original_id, approval)
      original_revision_id = DepartureBatch.where(id: original_id).pick(:revision_id)
      expected = OffseasonInputRevision.find(original_revision_id).payload
      unless expected.fetch('review').except(*ALLOWED_REVIEW_FIELDS) == approval.document.except(*ALLOWED_REVIEW_FIELDS)
        raise 'Original approval facts changed outside enumerated actor/time/version fields'
      end

      expected['review'] = approval.document
      expected['review_hash'] = approval.review_hash
      expected.fetch('report')['reviewed_revision'] = approval.review_hash
      expected
    end

    def self.verify_expected_payload(id, expected)
      revision = OffseasonInputRevision.select(:id, :input_hash).find(id)
      raise 'Original canonical payload hash differs' unless revision.input_hash == Departures::Contract.digest(expected)

      template = 'SELECT payload::text = :expected::jsonb::text FROM offseason_input_revisions WHERE id = :id'
      query = ApplicationRecord.sanitize_sql_array([template, { expected: JSON.generate(expected), id: }])
      raise 'Original complete payload differs' unless ApplicationRecord.connection.select_value(query)
    end
  end
end
