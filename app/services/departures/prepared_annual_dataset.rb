# frozen_string_literal: true

module Departures
  # A fresh certificate uses scalar references, avoiding mutable annual-header snapshots in ActiveRecord.
  class PreparedAnnualDataset < AnnualRowWriter
    # The SQL header expression and its optional JSON bind travel together.
    Insertion = Data.define(:sql, :header)

    INSERT_SQL = <<~SQL.squish.freeze
      INSERT INTO departure_dataset_normalizations (identity, header, source_normalization_ids)
      VALUES ($1, $2::jsonb, $3::jsonb) RETURNING id
    SQL

    def self.call(header, sources)
      new(reference(header, sources, Insertion.new(sql: INSERT_SQL, header: JSON.generate(header))), sources).call
    end

    def self.legacy(header, sources, attempt_id)
      sql = INSERT_SQL.sub('$2::jsonb', "COALESCE($2::jsonb, #{legacy_header_sql(attempt_id)})")
      new(reference(header, sources, Insertion.new(sql:, header: nil)), sources).call
    end

    def self.reference(header, sources, insertion)
      ids = sources.transform_values(&:id)
      id = insert(insertion, ids)
      DepartureDatasetNormalization::Reference.new(id:, header:, source_normalization_ids: ids, dataset_revision: nil, summary: {})
    end

    def self.insert(insertion, ids)
      values = [SecureRandom.uuid, insertion.header, JSON.generate(ids)]
      binds = values.map { |value| ActiveRecord::Relation::QueryAttribute.new('departure_header', value, ActiveRecord::Type::String.new) }
      ApplicationRecord.connection.exec_query(insertion.sql, 'Fresh departure dataset', binds).first.fetch('id')
    end

    def self.legacy_header_sql(attempt_id)
      template = <<~SQL.squish
        (SELECT jsonb_object_agg(key, value) || :additions::jsonb FROM departure_acquisitions,
          LATERAL jsonb_each(manifest) WHERE id = :attempt_id AND key IN
          ('draft_year', 'prior_season_year', 'target_year', 'expected_picks', 'predecessor', 'sources'))
      SQL
      additions = JSON.generate('schema' => Contract::VERSION, 'extraction_version' => Contract::EXTRACTION)
      ApplicationRecord.sanitize_sql_array([template, { attempt_id:, additions: }])
    end

    def initialize(record, sources)
      super
      @connection = ApplicationRecord.connection
    end

    def call
      @connection.transaction do
        DepartureDatasetNormalization.where(id: record.id).lock.pick(:id)
        prepare_rows
      end
    end

    private

    def prepare_rows
      @settings = record.header
      populate
      complete_reference(completion)
    end

    def complete_reference(attributes)
      template = "UPDATE departure_dataset_normalizations SET status = 'completed', dataset_revision = :revision, " \
                 'summary = :summary::jsonb WHERE id = :id'
      values = { revision: attributes.fetch(:dataset_revision), summary: JSON.generate(attributes.fetch(:summary)), id: record.id }
      @connection.execute(ApplicationRecord.sanitize_sql_array([template, values]))
      record.with(**attributes.except(:status))
    end

    def completion
      summary = DatasetStream::KINDS.index_with { |kind| record.rows.where(kind:).count }
      { status: 'completed', dataset_revision: PersistedDatasetStream.new(record).digest, summary: }
    end
  end
end
