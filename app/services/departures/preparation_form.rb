# frozen_string_literal: true

module Departures
  # Validates operator fields before any preparation or evidence is changed.
  class PreparationForm
    def initialize(attributes, season)
      @attributes = attributes
      @season = season
    end

    def call
      Contract.check!(attributes.fetch('sources', {}).empty?, 'New acquisition is CBBD-only; create a CBBD successor')
      plan = years.merge(provider_fields)
      CbbdDataset.validate_plan(plan)
      Contract.years!(plan)
      plan.merge('sources' => CbbdDataset.sources(plan))
    end

    def self.integer(value)
      text = value.to_s
      Contract.check!(text.match?(/\A\d+\z/), 'Years and picks must be explicit whole numbers')
      Integer(text, 10)
    end

    def self.defaults(target_year)
      year = target_year - 1
      { 'draft_year' => year, 'prior_season_year' => year, 'target_year' => target_year, 'expected_picks' => '',
        'scope_evidence' => '', 'max_requests' => 15, 'retries' => 2, 'absent_postseason_team_ids' => '' }
    end

    private

    attr_reader :attributes, :season

    def provider_fields
      parser = self.class
      { 'provider' => 'cbbd', 'schema' => CbbdDataset::VERSION, 'extraction_version' => CbbdDataset::EXTRACTION,
        'expected_picks' => picks, 'scope_evidence' => attributes.fetch('scope_evidence'),
        'max_requests' => parser.integer(attributes.fetch('max_requests')), 'retries' => parser.integer(attributes.fetch('retries')),
        'absent_postseason_team_ids' => absent_postseason_ids }
    end

    def absent_postseason_ids
      attributes.fetch('absent_postseason_team_ids', '').to_s.split(/[\s,]+/).map { |value| self.class.integer(value) }
    end

    def years
      plan = %w[draft_year prior_season_year target_year].index_with { |key| self.class.integer(attributes.fetch(key)) }
      Contract.check!(plan['target_year'] == season.year, 'Departure target season mismatch')
      require_memberships
      plan
    end

    def require_memberships
      Contract.check!(season.team_seasons.exists?, 'Prepare target-season team memberships first')
    end

    def picks
      attributes.fetch('expected_picks').to_s.split(/[\s,]+/).map { |value| self.class.integer(value) }
    end
  end
end
