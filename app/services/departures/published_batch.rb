# frozen_string_literal: true

module Departures
  # An automatic proposal retains its derived annual policy only when the exact approval publishes.
  class PublishedBatch
    ATTEMPT_SQL = <<~SQL.squish.freeze
      INSERT INTO departure_acquisitions
        (departure_batch_id, predecessor_id, plan, manifest, dataset, evidence, status, started_at, finished_at, created_at, updated_at)
      SELECT :batch_id, a.id, :plan_json::jsonb, n.header,
        jsonb_build_object('storage_version', :storage_version, 'normalization_id', n.id,
          'dataset_revision', n.dataset_revision, 'summary', n.summary), a.evidence, 'completed',
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM departure_acquisitions a CROSS JOIN departure_dataset_normalizations n
      WHERE a.id = :attempt_id AND n.id = :normalization_id
    SQL

    def initialize(approval, batch)
      @approval = approval
      @operation = approval.departure_validation
      @batch = batch
    end

    def call(revision_id)
      document = @approval.document
      attributes = { status: 'published', revision_id:, reviewed_by: @approval.reviewed_by, reviewed_at: @approval.reviewed_at,
                     acknowledgement: document.fetch('partial_acknowledgement') }
      attributes.merge!(automatic_attributes(document)) if @operation.choices['automatic']
      @batch.update!(attributes)
    end

    private

    def automatic_attributes(document)
      plan = DepartureDatasetNormalization.where(id: @operation.departure_dataset_normalization_id)
                                          .pick(Arel.sql("header - 'sources' - 'captures'"))
      retain_attempt(plan)
      { plan:, decisions: document.fetch('decisions') }
    end

    def retain_attempt(plan)
      values = { batch_id: @batch.id, plan_json: JSON.generate(plan), storage_version: StoredDataset::VERSION,
                 attempt_id: @operation.departure_acquisition_id, normalization_id: @operation.departure_dataset_normalization_id }
      ApplicationRecord.connection.execute(ApplicationRecord.sanitize_sql_array([ATTEMPT_SQL, values]))
    end
  end
end
