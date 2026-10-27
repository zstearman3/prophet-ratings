# frozen_string_literal: true

module Departures
  # Worker-only authentication of actual retained bytes and the annual rows consumed by publication.
  class ValidationArtifacts
    METADATA_SQL = <<~SQL.squish.freeze
      jsonb_build_object('plan_hash', md5(plan::text), 'manifest', manifest - 'sources' - 'captures',
                        'status', status, 'predecessor_id', predecessor_id)
    SQL

    def initialize(operation)
      @operation = operation
      @attempt_id = operation.departure_acquisition_id
      @source_hash = nil
    end

    def call
      record = record_reference
      { 'sources' => source_digest, 'annual' => PersistedDatasetStream.new(record).digest,
        'dataset_revision' => record.dataset_revision, 'evidence' => evidence_digest }
    end

    private

    def record_reference
      id = @operation.departure_dataset_normalization_id
      header, revision = DepartureDatasetNormalization.where(id:).pick(Arel.sql("header - 'sources' - 'captures'"), :dataset_revision)
      DepartureDatasetNormalization::Reference.new(id:, header:, dataset_revision: revision, source_normalization_ids: {}, summary: {})
    end

    def source_digest
      metadata = DepartureAcquisition.where(id: @attempt_id).pick(Arel.sql(METADATA_SQL))
      @source_hash = Digest::SHA256.new << JSON.generate(metadata, sort_keys: true)
      %w[sources captures].each { |key| write_sources(key) }
      @source_hash.hexdigest
    end

    def write_sources(key)
      @source_hash << key
      SourceMetadata.new(@attempt_id, key).each { |source| write_source(source) }
    end

    def reader
      @reader ||= RetainedSourceReader.new(@attempt_id)
    end

    def write_source(source)
      @source_hash << JSON.generate(source, sort_keys: true)
      @source_hash << Digest::SHA256.hexdigest(reader.bytes(source)) if source['snapshot_location']
      @source_hash << JSON.generate(reader.observation_identity(source), sort_keys: true)
    end

    def evidence_digest
      hash = Digest::SHA256.new
      EvidenceStream.new(@attempt_id, hash).call
      hash.hexdigest
    end
  end
end
