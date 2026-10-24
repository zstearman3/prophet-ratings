# frozen_string_literal: true

module Departures
  # Presents validated retained rows without treating observed picks or absent rows as confirmations.
  class CoverageEvidence
    def initialize(attempt)
      @attempt = attempt
      @sources = RetainedEvidence.new(attempt).captured_sources
    end

    def call
      context = { 'selections' => [], 'sources' => source_summary, 'no_postseason_teams' => [], 'production_warnings' => [] }
      normalize(context)
    end

    private

    attr_reader :attempt, :sources

    def rows(id)
      sources.find { |source| source['id'] == id }.fetch('rows', [])
    end

    def selections
      CbbdSelections.new(rows('draft'), attempt.plan).call
    end

    def source_summary
      sources.map { |source| self.class.summarize(source) }
    end

    public_class_method def self.summarize(source)
      source.except('rows').merge('row_count' => source.fetch('rows', []).size)
    end

    def normalize(context)
      context['selections'] = selections
      tables = production
      context.merge('no_postseason_teams' => self.class.named_absences(tables, sources),
                    'production_warnings' => CbbdProduction.warnings(tables), 'errors' => [])
    rescue ArgumentError, KeyError, TypeError => error
      context.merge('errors' => [error.message])
    end

    def production
      settings = attempt.plan.merge('scope_evidence' => 'Unreviewed retained scopes', 'absent_postseason_team_ids' => [],
                                    'extraction_version' => CbbdDataset::REPORTED_TOTALS_EXTRACTION)
      CbbdProduction.new(parsed: sources, settings:).call
    end

    public_class_method def self.postseason_succeeded?(sources)
      sources.index_by { |source| source.fetch('id') }.values_at('player-postseason', 'team-postseason')
             .none? { |source| source['failure'] }
    end

    public_class_method def self.named_absences(teams, sources)
      return [] unless postseason_succeeded?(sources)

      teams.select { |team| eligible_absence?(team) }.map { |team| named_team(team) }
    end

    public_class_method def self.eligible_absence?(team)
      scopes = team.fetch('scope_rows')
      scopes['regular']&.fetch('complete') && !scopes['postseason']
    end

    public_class_method def self.named_team(production)
      id = production.fetch('provider_team_id')
      team = TeamExternalIdentity.find_by(provider: 'cbbd', external_id: id.to_s)&.team
      production.slice('provider_team_id', 'team_name_source').merge('team_id' => team&.id, 'team_name' => team&.school)
    end
  end
end
