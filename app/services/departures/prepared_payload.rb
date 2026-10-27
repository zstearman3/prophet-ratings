# frozen_string_literal: true

module Departures
  # Hashes the original contract in bounded pieces; all SQL values use the same bound template.
  class PreparedPayload
    SQL = <<~SQL.squish.freeze
      jsonb_build_object('kind', 'departures', 'dataset_hash', :dataset_revision,
        'review_hash', :review_hash, 'dataset', DATASET_EXPRESSION, 'review', :review_json::jsonb,
        'report', :report_json::jsonb,
        'evidence', (SELECT evidence FROM departure_acquisitions WHERE id = :attempt_id),
        'team_inputs', (SELECT jsonb_object_agg(team_id::text, input) FROM departure_proposals WHERE departure_validation_id = :operation_id))
    SQL
    INSERT_SQL = <<~SQL.squish.freeze
      INSERT INTO offseason_input_revisions
        (season_id, kind, version, reason, predecessor_id, input_hash, dataset_hash, review_hash, payload, created_at, updated_at)
      VALUES (:season_id, 'departures', :version, :reason, :predecessor_id, :input_hash, :dataset_revision, :review_hash,
        PAYLOAD_EXPRESSION, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id
    SQL

    def initialize(approval)
      @approval = approval
      @operation = approval.departure_validation
      @record = record_reference
    end

    def report
      @operation.report.except('gaps').merge('reviewed_revision' => @approval.review_hash)
    end

    def digest
      hash = Digest::SHA256.new
      write_dataset(hash)
      EvidenceStream.new(@operation.departure_acquisition_id, hash).call
      hash << ',' << JSON.generate(metadata, sort_keys: true).delete_prefix('{')
      hash.hexdigest
    end

    def metadata
      inputs = @operation.proposals.order(Arel.sql('team_id::text COLLATE "C"')).pluck(:team_id, :input).to_h.transform_keys(&:to_s)
      { 'kind' => 'departures', 'report' => report, 'review' => @approval.document, 'review_hash' => @approval.review_hash,
        'team_inputs' => inputs }
    end

    def sql
      ApplicationRecord.sanitize_sql_array([sql_template, bindings])
    end

    def insert_revision(attributes)
      template = INSERT_SQL.sub('PAYLOAD_EXPRESSION', sql_template)
      query = ApplicationRecord.sanitize_sql_array([template, bindings.merge(attributes)])
      ApplicationRecord.connection.select_value(query).to_i
    end

    def matches_revision?(revision_id)
      template = "SELECT payload::text = (#{sql_template})::text FROM offseason_input_revisions WHERE id = :revision_id"
      query = ApplicationRecord.sanitize_sql_array([template, bindings.merge(revision_id:)])
      ApplicationRecord.connection.select_value(query)
    end

    private

    def record_reference
      id = @operation.departure_dataset_normalization_id
      header, revision = DepartureDatasetNormalization.where(id:).pick(Arel.sql("header - 'sources' - 'captures'"), :dataset_revision)
      DepartureDatasetNormalization::Reference.new(id:, header:, dataset_revision: revision, source_normalization_ids: {}, summary: {})
    end

    def write_dataset(hash)
      hash << '{"dataset":'
      PersistedDatasetStream.new(@record, keys: ['dataset_revision']).write(hash)
      hash << ',"dataset_hash":' << JSON.generate(@record.dataset_revision) << ',"evidence":'
    end

    def sql_template
      SQL.sub('DATASET_EXPRESSION', PreparedDataset.new(@record).sql_template)
    end

    def bindings
      { normalization_id: @record.id, dataset_revision: @record.dataset_revision, review_hash: @approval.review_hash,
        review_json: JSON.generate(@approval.document), report_json: JSON.generate(report),
        attempt_id: @operation.departure_acquisition_id, operation_id: @operation.id }
    end
  end
end
