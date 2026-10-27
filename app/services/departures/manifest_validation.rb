# frozen_string_literal: true

module Departures
  # Preserve the file reader's original contract guards before canonicalizing any legacy header.
  class ManifestValidation
    def initialize(attempt_id, manifest)
      @attempt_id = Integer(attempt_id)
      @manifest = manifest
    end

    def call
      Contract.years!(@manifest)
      @manifest['provider'] == 'cbbd' ? cbbd : legacy
    end

    private

    def cbbd
      CapturePreparation.validate_acquisition_plan(@manifest.except('sources', 'captures'))
      requests = CbbdDataset.sources(@manifest)
      StoredSources.validate_requests(@manifest.fetch('sources'), requests)
      StoredSources.validate_ledger(@manifest, requests.pluck('request'))
    end

    def legacy
      PlayerIdentity.validate_contract(@manifest)
      Contract.check!([nil, Contract::EXTRACTION].include?(@manifest['extraction_version']), 'Unsupported departure extraction contract')
      AnnualDataset.validate_picks(@manifest.fetch('expected_picks'))
      source_contract
    end

    def source_contract
      type = DepartureAcquisition.where(id: @attempt_id).pick(Arel.sql("jsonb_typeof(manifest->'sources')"))
      Contract.check!(type == 'array', 'Require one NBA results source')
      count, unique, drafts = ApplicationRecord.connection.select_rows(source_counts).first.map(&:to_i)
      Contract.check!(drafts == 1, 'Require one NBA results source')
      Contract.check!(count == unique, 'Duplicate source IDs')
    end

    def source_counts
      <<~SQL.squish
        SELECT count(*), count(DISTINCT source->>'id'), count(*) FILTER (WHERE source->>'type' = 'nba_results')
        FROM departure_acquisitions, LATERAL jsonb_array_elements(manifest->'sources') source WHERE id = #{@attempt_id}
      SQL
    end
  end
end
