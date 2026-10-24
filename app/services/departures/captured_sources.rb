# frozen_string_literal: true

module Departures
  # The capture contract validates every retry and selected response without annual assertions.
  class CapturedSources
    def initialize(attempt, directory)
      @plan = attempt.plan
      @manifest = attempt.manifest
      @directory = directory
    end

    def call
      validate_plan
      validate_manifest
      validate_ledger
      sources.map { |source| CbbdSnapshot.new(source:, directory:, settings: plan).call }
    end

    private

    attr_reader :plan, :manifest, :directory

    def validate_plan
      CapturePreparation.validate_acquisition_plan(plan)
      Contract.years!(plan)
    end

    def sources
      manifest.fetch('sources')
    end

    def validate_manifest
      Contract.check!(manifest.except('sources', 'captures') == plan.except('sources'), 'Retained preparation mismatch')
      expected = CbbdDataset.sources(plan)
      actual = sources.map { |source| source.slice('id', 'type', 'url', 'request') }
      Contract.check!(actual.to_set == expected.to_set && actual.size == expected.size, 'Invalid retained source requests')
    end

    def validate_ledger
      captures = CbbdDataset.capture_index(manifest, directory)
      CbbdDataset.validate_selected(sources, captures)
    end
  end
end
