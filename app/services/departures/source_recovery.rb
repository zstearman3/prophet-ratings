# frozen_string_literal: true

module Departures
  # Replaces one uploaded source in a new acquisition, preserving every other original byte in SQL.
  class SourceRecovery
    SQL = <<~SQL.squish.freeze
      INSERT INTO departure_acquisitions
        (departure_batch_id, predecessor_id, plan, manifest, dataset, evidence, status, started_at, finished_at, created_at, updated_at)
      SELECT departure_batch_id, id, plan,
        jsonb_set(manifest, '{sources}', (SELECT jsonb_agg(CASE WHEN value->>'id' = :source_id THEN :replacement_json::jsonb ELSE value END ORDER BY ordinal)
          FROM jsonb_array_elements(manifest->'sources') WITH ORDINALITY AS sources(value, ordinal))),
        :pending_json::jsonb, evidence || :evidence_json::jsonb, 'completed',
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM departure_acquisitions WHERE id = :original_id AND departure_batch_id = :batch_id
        AND id = (SELECT MAX(id) FROM departure_acquisitions WHERE departure_batch_id = :batch_id) RETURNING id
    SQL

    def initialize(batch)
      @batch = batch
    end

    def call(attributes)
      original_id = validate_original
      source = SourceHistory.new(@batch, attempt_id: original_id).source(attributes.fetch('source_id'))
      replacement, evidence = UploadedSource.new(source, attributes).call
      retain(original_id, replacement, evidence)
      ValidationPreparation.queue(@batch)
    end

    private

    def validate_original
      Contract.check!(@batch.status == 'draft', 'Published departure batches are closed; start a correction')
      original = @batch.acquisitions.select(:id, :status, Arel.sql("plan->>'provider' AS provider")).order(:id).last
      Contract.check!(original&.terminal?, 'Wait for acquisition to finish before recovery')
      Contract.check!(!original.provider, 'CBBD recovery requires a new bounded acquisition; JSON upload is not supported')
      original.id
    end

    def retain(original_id, replacement, evidence)
      DepartureBatch.transaction do
        ValidationPreparation.lock_generation_nowait
        batch = locked_draft
        retain_acquisition(self.class.bindings(original_id, replacement, evidence))
        batch.update!(decisions: [], acknowledgement: {})
      end
    end

    def locked_draft
      batch = DepartureBatch.select(DepartureBatch.column_names - ['plan']).lock.find(@batch.id)
      Contract.check!(batch.status == 'draft', 'Published departure batches are closed; start a correction')
      batch
    end

    def retain_acquisition(values)
      query = ApplicationRecord.sanitize_sql_array([SQL, values.merge(batch_id: @batch.id)])
      Contract.check!(ApplicationRecord.connection.select_value(query), 'Departure acquisition changed; reload')
    end

    public_class_method def self.bindings(original_id, replacement, evidence)
      id = replacement.fetch('id')
      { source_id: id, replacement_json: JSON.generate(replacement), pending_json: JSON.generate('storage_version' => BatchSuccessor::PENDING),
        evidence_json: JSON.generate(id => evidence), original_id: }
    end
  end
end
