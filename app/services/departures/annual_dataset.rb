# frozen_string_literal: true

module Departures
  # Constructs a factual dataset without any reviewed mappings or database writes.
  class AnnualDataset
    def initialize(manifest:, directory:)
      @manifest = manifest
      @directory = directory
      Contract.years!(manifest)
      validate_sources
    end

    def call
      parser = self.class
      parsed = snapshots.map(&:call)
      dataset = attributes.merge('selections' => parser.selections(parsed), 'production' => parser.production(parsed),
                                 'failures' => parsed.select { |entry| entry['failure'] })
      dataset.merge('dataset_revision' => Contract.hash(dataset))
    end

    def self.selections(parsed)
      rows = parsed.select { |entry| entry['type'] == 'nba_results' }.flat_map { |entry| entry.fetch('rows', []) }
      NbaResults.validate_rows(rows) unless rows.empty?
      rows
    end

    def self.production(parsed)
      parsed.select { |entry| entry['type'] == 'sidearm_totals' && entry['rows'] }.pluck('rows')
    end

    def self.validate_picks(picks)
      Contract.check!(picks.is_a?(Array) && picks.any? && picks.all? { |pick| pick.is_a?(Integer) && (1..60).cover?(pick) },
                      'expected_picks must explicitly list actual selections, excluding rescinded picks')
      Contract.unique!(picks, 'expected picks')
    end

    private

    attr_reader :manifest, :directory

    def attributes
      manifest.slice('draft_year', 'prior_season_year', 'target_year', 'expected_picks', 'predecessor')
              .merge('schema' => Contract::VERSION, 'extraction_version' => Contract::EXTRACTION, 'sources' => sources)
    end

    def sources
      manifest.fetch('sources')
    end

    def snapshots
      sources.map { |source| SourceSnapshot.new(source:, directory:, settings: manifest) }
    end

    def validate_sources
      self.class.validate_picks(manifest.fetch('expected_picks'))
      Contract.check!(sources.is_a?(Array) && sources.one? { |source| source['type'] == 'nba_results' }, 'Require one NBA results source')
      Contract.unique!(sources.pluck('id'), 'source IDs')
      snapshots
    end
  end
end
