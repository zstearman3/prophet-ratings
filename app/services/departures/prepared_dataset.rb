# frozen_string_literal: true

module Departures
  # Complete representational equality stays in PostgreSQL; the browser never loads annual JSON.
  class PreparedDataset
    ARRAY_SQL = DatasetStream::KINDS.index_with do |kind|
      "'#{kind}', COALESCE((SELECT jsonb_agg(fact::jsonb ORDER BY ordinal) FROM departure_dataset_rows " \
        "WHERE departure_dataset_normalization_id = :normalization_id AND kind = '#{kind}'), '[]'::jsonb)"
    end.freeze
    SQL = [DatasetStream::KINDS.first(3), DatasetStream::KINDS].map do |kinds|
      "(SELECT header || jsonb_build_object(#{kinds.map { |kind| ARRAY_SQL.fetch(kind) }.join(', ')}) || " \
        "jsonb_build_object('dataset_revision', dataset_revision) FROM departure_dataset_normalizations WHERE id = :normalization_id)"
    end.freeze

    def initialize(record)
      @record = record
    end

    def sql_template
      header = @record.header
      SQL.fetch(CbbdDataset.reported_totals?(header) && header['schema'] == CbbdDataset::VERSION ? 1 : 0)
    end

    def sql
      ApplicationRecord.sanitize_sql_array([sql_template, { normalization_id: @record.id }])
    end

    def validate_saved(attempt_id)
      reference, revision = DepartureAcquisition.where(id: attempt_id).pick(Arel.sql("dataset->>'storage_version'"),
                                                                            Arel.sql("dataset->>'dataset_revision'"))
      valid = reference == StoredDataset::VERSION ? revision == @record.dataset_revision : saved_equal?(attempt_id)
      Contract.check!(valid, 'Retained departure dataset differs from replay')
    end

    def projection(decisions)
      data = projection_header
      tables = ProductionProjection.new(@record, data, decisions).call
      data.merge('production' => tables, 'sources' => self.class.source_metadata(data, decisions, tables))
    end

    def self.source_metadata(data, decisions, tables)
      sources = data.fetch('sources')
      return sources if data['provider'] == 'cbbd'

      ids = decisions.flat_map { |decision| decision_evidence(decision) } + tables.pluck('source_id')
      select_sources(sources, ids)
    end

    def self.select_sources(sources, ids)
      sources.select { |source| ids.include?(source.fetch('id')) }
    end

    def self.decision_evidence(decision)
      decision.fetch('evidence_source_ids', []) + decision.fetch('stints', []).flat_map do |stint|
        stint.fetch('identity_evidence_source_ids', [])
      end
    end

    private

    def saved_equal?(attempt_id)
      template = "SELECT dataset::text = #{sql_template}::text FROM departure_acquisitions WHERE id = :attempt_id"
      query = ApplicationRecord.sanitize_sql_array([template, { normalization_id: @record.id, attempt_id: }])
      ApplicationRecord.connection.select_value(query)
    end

    def projection_kinds
      header = @record.header
      if header['schema'] == CbbdDataset::VERSION && CbbdDataset.reported_totals?(header)
        %w[selections failures
           production_warnings]
      else
        %w[selections failures]
      end
    end

    def projection_header
      data = @record.header.merge('dataset_revision' => @record.dataset_revision)
      projection_kinds.each { |kind| data[kind] = @record.rows.where(kind:).order(:ordinal).pluck(:fact) }
      data
    end
  end
end
