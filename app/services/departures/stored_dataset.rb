# frozen_string_literal: true

module Departures
  # Source parsing is reusable; each frozen annual policy has its own logical identity.
  class StoredDataset
    VERSION = 'departure-dataset-v1'

    def initialize(attempt)
      @attempt = attempt
    end

    def call
      sources = parsed_sources
      ids = sources.transform_values(&:id)
      record = normalization(ids)
      AnnualRowWriter.new(record, sources).call unless record.status == 'completed'
      record
    end

    def normalization(ids)
      identity = Contract.digest([VERSION, @attempt.manifest, ids])
      DepartureDatasetNormalization.create_or_find_by!(identity:) { |row| row.assign_attributes(header:, source_normalization_ids: ids) }
    end

    def self.reference(record)
      { 'storage_version' => VERSION, 'normalization_id' => record.id, 'dataset_revision' => record.dataset_revision,
        'summary' => record.summary }
    end

    def verify(record)
      StoredDatasetVerification.new(self, record).call
    end

    def parsed_sources
      StoredSources.new(@attempt).call
    end

    def header
      self.class.header(@attempt.manifest)
    end

    def self.header(manifest)
      return manifest.except('dataset_revision') if manifest['schema'] == CbbdDataset::VERSION

      manifest.slice('draft_year', 'prior_season_year', 'target_year', 'expected_picks', 'predecessor', 'sources')
              .merge('schema' => Contract::VERSION, 'extraction_version' => Contract::EXTRACTION)
    end
  end
end
