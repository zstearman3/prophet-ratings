# frozen_string_literal: true

module Departures
  # Replay validates normalized-source integrity and recalculates all policy-dependent annual values.
  class StoredDatasetVerification
    def initialize(normalizer, record)
      @normalizer = normalizer
      @record = record
    end

    def call
      sources = @normalizer.parsed_sources
      validate_sources(sources)
      verify_replay(sources)
      @record
    end

    private

    def validate_sources(sources)
      Contract.check!(@record.status == 'completed', 'Incomplete departure normalization')
      Contract.check!(sources.transform_values(&:id) == @record.source_normalization_ids, 'Departure source normalization mismatch')
      sources.each_value { |source| self.class.validate_source(source) }
    end

    public_class_method def self.validate_source(source)
      digest = DatasetStream.rows_digest(source.rows.order(:ordinal))
      Contract.check!(source.status == 'completed' && digest == source.rows_digest, 'Normalized departure source rows differ')
    end

    def verify_replay(sources)
      scratch = DepartureDatasetNormalization.create!(identity: SecureRandom.uuid, header: @normalizer.header,
                                                      source_normalization_ids: @record.source_normalization_ids)
      AnnualRowWriter.new(scratch, sources).call
      revision = @record.dataset_revision
      Contract.check!(scratch.dataset_revision == revision && DatasetStream.new(@record).digest == revision,
                      'Retained departure dataset differs from replay')
    ensure
      self.class.remove_scratch(scratch) if scratch
    end

    public_class_method def self.remove_scratch(scratch)
      scratch.rows.delete_all(:delete_all)
      DepartureDatasetNormalization.where(id: scratch.id).delete_all
    end
  end
end
