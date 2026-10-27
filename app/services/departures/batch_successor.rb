# frozen_string_literal: true

module Departures
  # Copies complete retained JSON in PostgreSQL; browser actions never expand annual evidence.
  class BatchSuccessor
    PENDING = 'departure-validation-pending-v1'
    BATCH_SQL = <<~SQL.squish.freeze
      INSERT INTO departure_batches (season_id, predecessor_id, status, plan, decisions, acknowledgement, correction_reason, created_at, updated_at)
      SELECT season_id, id, 'draft', plan, decisions, '{}'::jsonb, :reason, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM departure_batches WHERE id = :batch_id AND status = 'published' RETURNING id
    SQL
    COPY_SQL = <<~SQL.squish.freeze
      INSERT INTO departure_acquisitions
        (departure_batch_id, predecessor_id, plan, manifest, dataset, evidence, status, failure, started_at, finished_at, created_at, updated_at)
      SELECT :correction_id, id, plan, manifest, dataset, evidence, status, failure, started_at, finished_at, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM departure_acquisitions WHERE departure_batch_id = :batch_id ORDER BY id DESC LIMIT 1
    SQL
    COVERAGE_SQL = <<~SQL.squish.freeze
      INSERT INTO departure_acquisitions
        (departure_batch_id, predecessor_id, plan, manifest, dataset, evidence, status, started_at, finished_at, created_at, updated_at)
      SELECT departure_batch_id, id, :plan_json::jsonb,
        :plan_json::jsonb || (manifest - ARRAY(SELECT jsonb_object_keys(manifest - 'sources' - 'captures'))),
        :pending_json::jsonb, evidence, 'completed', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM departure_acquisitions WHERE id = :predecessor_id AND departure_batch_id = :batch_id
    SQL

    def initialize(batch)
      @batch = batch
    end

    def correct(reason)
      Contract.text!(reason, 'correction reason')
      id = ValidationLocks.web_transaction do
        DepartureBatch.select(:id).lock('FOR UPDATE NOWAIT').find(@batch.id)
        copy_batch(reason)
      end
      self.class.queued_correction(id)
    end

    def recover(attributes)
      SourceRecovery.new(@batch).call(attributes)
    end

    def coverage(plan, predecessor_id)
      values = { plan_json: JSON.generate(plan), pending_json: JSON.generate('storage_version' => PENDING), predecessor_id:,
                 batch_id: @batch.id }
      ApplicationRecord.connection.execute(ApplicationRecord.sanitize_sql_array([COVERAGE_SQL, values]))
      editable_batch.update!(plan:, decisions: [], acknowledgement: {}, reviewed_by: nil, reviewed_at: nil)
    end

    private

    def editable_batch
      DepartureBatch.select(DepartureBatch.column_names - ['plan']).find(@batch.id)
    end

    public_class_method def self.queued_correction(id)
      correction = DepartureBatch.select(DepartureBatch.column_names - ['plan']).find(id)
      ValidationPreparation.queue(correction)
      correction
    end

    def copy_batch(reason)
      query = ApplicationRecord.sanitize_sql_array([BATCH_SQL, { batch_id: @batch.id, reason: }])
      id = ApplicationRecord.connection.select_value(query)
      Contract.check!(id, 'Only published batches can start corrections; reload')
      copy_attempt(id)
      id
    end

    def copy_attempt(correction_id)
      query = ApplicationRecord.sanitize_sql_array([COPY_SQL, { batch_id: @batch.id, correction_id: }])
      ApplicationRecord.connection.execute(query)
    end
  end
end
