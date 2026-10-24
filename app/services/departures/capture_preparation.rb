# frozen_string_literal: true

module Departures
  # Capture has bounded requests and derived years, but cannot certify annual coverage.
  class CapturePreparation < BatchPreparation
    VERSION = 'draft-departures-capture-v1'

    def self.create(season, attributes)
      DepartureBatch.transaction do
        batch = DepartureBatch.create!(season:, plan: build_plan(season, attributes))
        new(batch).acquire
        batch
      end
    end

    def self.capture_only?(plan)
      plan['schema'] == VERSION
    end

    def self.build_plan(season, attributes)
      Contract.check!(season.team_seasons.exists?, 'Prepare target-season team memberships first')
      Contract.check!(attributes.fetch('sources', {}).empty?, 'Capture source requests are server-generated')
      plan = capture_years(season, attributes).merge(capture_limits(attributes), 'provider' => 'cbbd',
                                                                                 'schema' => VERSION, 'extraction_version' => CbbdDataset::EXTRACTION)
      validate_plan(plan)
      plan.merge('sources' => CbbdDataset.sources(plan))
    end

    def self.validate_plan(plan)
      Contract.years!(plan)
      Contract.check!(plan.values_at('provider', 'schema', 'extraction_version') == ['cbbd', VERSION, CbbdDataset::EXTRACTION],
                      'Unsupported capture contract')
      Contract.check!(!plan.keys.intersect?(%w[expected_picks scope_evidence absent_postseason_team_ids coverage_review]),
                      'Capture cannot assert reviewed coverage')
      CbbdDataset.validate_limits(plan)
      validate_source_requests(plan)
    end

    def self.validate_source_requests(plan)
      return unless plan.key?('sources')

      expected = CbbdDataset.sources(plan)
      actual = plan.fetch('sources').map { |source| source.slice('id', 'type', 'url', 'request') }
      Contract.check!(actual.to_set == expected.to_set && actual.size == expected.size, 'Invalid capture source requests')
    end

    def self.capture_years(season, attributes)
      years = PreparationForm.defaults(season.year).slice('draft_year', 'prior_season_year', 'target_year')
      years.each do |key, year|
        Contract.check!(PreparationForm.integer(attributes.fetch(key, year)) == year, 'Capture years must match the target season')
      end
      years
    end

    def self.capture_limits(attributes)
      { 'max_requests' => 15, 'retries' => 2 }.merge(attributes.slice('max_requests', 'retries'))
                                              .transform_values { |value| PreparationForm.integer(value) }
    end

    def self.validate_acquisition_plan(plan)
      validator = capture_only?(plan) ? self : CbbdDataset
      validator.validate_plan(plan)
    end

    private

    def clear_review(plan)
      batch.update!(plan:, decisions: [], acknowledgement: {}, reviewed_by: nil, reviewed_at: nil)
    end

    def validate_queue
      batch.require_editable
      require_provider
    end

    def queue_attempt
      validate_queue
      plan = self.class.build_plan(batch.season, batch.plan.slice('max_requests', 'retries'))
      attempt = batch.acquisitions.create!(plan:, predecessor: batch.attempt)
      clear_review(plan)
      attempt
    end
  end
end
