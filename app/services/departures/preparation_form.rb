# frozen_string_literal: true

module Departures
  # Validates operator fields before any preparation or evidence is changed.
  class PreparationForm
    def initialize(attributes, season)
      @attributes = attributes
      @season = season
    end

    def call
      plan = years.merge('expected_picks' => picks, 'sources' => sources)
      AnnualDataset.new(manifest: plan, directory: '.')
      plan
    end

    def self.integer(value)
      text = value.to_s
      Contract.check!(text.match?(/\A\d+\z/), 'Years and picks must be explicit whole numbers')
      Integer(text, 10)
    end

    def self.source(source, index)
      fields = source.slice('type', 'url', 'team_name_source', 'scope_evidence').merge('id' => "source-#{index + 1}")
      validate_school(fields) if fields['type'] == 'sidearm_totals'
      fields
    end

    def self.validate_school(fields)
      Contract.text!(fields['team_name_source'], 'school name')
      Contract.text!(fields['scope_evidence'], 'final overall scope evidence')
      fields['scope'] = Contract::SCOPE
    end

    def self.defaults(target_year)
      year = target_year - 1
      { 'draft_year' => year, 'prior_season_year' => year, 'target_year' => target_year, 'expected_picks' => '',
        'sources' => { '0' => { 'type' => 'nba_results', 'url' => "https://www.nba.com/news/#{year}-nba-draft-order" } } }
    end

    def self.add_source(preparation)
      sources = preparation.fetch('sources', {})
      count = sources.size
      Contract.check!(count < BatchPreparation::MAX_SOURCES, 'At most 200 sources are supported')
      sources["new-#{count}"] = { 'type' => 'sidearm_totals' }
    end

    private

    attr_reader :attributes, :season

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

    def sources
      rows = attributes.fetch('sources', {}).values.reject { |source| source['remove'] == '1' }
      Contract.check!(rows.size <= BatchPreparation::MAX_SOURCES, "At most #{BatchPreparation::MAX_SOURCES} sources are supported")
      rows.map.with_index { |source, index| self.class.source(source, index) }
    end
  end
end
