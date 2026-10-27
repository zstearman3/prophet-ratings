# frozen_string_literal: true

module Departures
  # Full source authentication remains worker-only; annual policy and saved-data comparison follow it.
  class ValidationEvidence
    def initialize(operation)
      @operation = operation
    end

    def call
      validate_preparation
      sources = parsed_sources
      record = normalize(sources)
      PreparedDataset.new(record).validate_saved(attempt_id) unless guided? || ValidationDatasetRetention.new(@operation).pending?
      record
    end

    private

    def attempt_id
      @operation.departure_acquisition_id
    end

    def manifest
      @manifest ||= load_manifest
    end

    def load_manifest
      attempt = DepartureAcquisition.where(id: attempt_id)
      lean = attempt.pick(Arel.sql("manifest - 'sources' - 'captures'"))
      return attempt.pick(:manifest) if lean['provider'] == 'cbbd'

      lean.merge('sources' => SourceMetadata.new(attempt_id, 'sources'), 'captures' => SourceMetadata.new(attempt_id, 'captures'))
    end

    def reader
      @reader ||= RetainedSourceReader.new(attempt_id)
    end

    def validate_preparation
      sql = <<~SQL.squish
        SELECT a.plan = b.plan FROM departure_acquisitions a JOIN departure_batches b ON b.id = a.departure_batch_id
        WHERE a.id = :attempt_id AND b.id = :batch_id
          AND a.status IN ('completed', 'incomplete', 'failed')
          AND a.id = (SELECT MAX(latest.id) FROM departure_acquisitions latest WHERE latest.departure_batch_id = b.id)
      SQL
      query = ApplicationRecord.sanitize_sql_array([sql, { attempt_id:, batch_id: @operation.departure_batch_id }])
      Contract.check!(ApplicationRecord.connection.select_value(query), 'Preparation changed; acquire fresh evidence')
    end

    def parsed_sources
      ManifestValidation.new(attempt_id, manifest).call
      manifest.fetch('captures', []).each { |source| reader.bytes(source) }
      manifest.fetch('sources').each_with_object({}) { |source, parsed| parse_source(source, parsed) }
    end

    def parse_source(source, parsed)
      SourceSnapshot.new(source:, directory: nil, settings: manifest) unless manifest.key?('provider')
      bytes = reader.bytes(source) if source['snapshot_location']
      parsed[source.fetch('id')] = normalize_source(source, bytes) if StoredSources.successful?(source)
    end

    def normalize_source(source, bytes)
      record = SourceNormalizer.new(source, bytes, manifest, identity: SecureRandom.uuid).call
      self.class.require_completed(record, source.fetch('id'))
    end

    public_class_method def self.require_completed(record, id)
      Contract.check!(record.status == 'completed', "Source #{id}: #{record.failure}")
      record
    end

    def guided?
      status = DepartureBatch.where(id: @operation.departure_batch_id).pick(:status)
      status == 'draft' && EffectiveDraftPlan.applicable?(manifest)
    end

    def normalize(sources)
      effective = guided? ? EffectiveDraftPlan.new(manifest, sources).call : manifest
      header = StoredDataset.header(effective)
      return PreparedAnnualDataset.legacy(header, sources, attempt_id) unless manifest.key?('provider')

      PreparedAnnualDataset.call(header, sources)
    end
  end
end
