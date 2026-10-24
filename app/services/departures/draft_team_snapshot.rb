# frozen_string_literal: true

module Departures
  # Freezes the existing prior-season identity scope without changing memberships or raw evidence.
  class DraftTeamSnapshot
    POLICY = 'successful_retained_regular_plus_postseason'

    def initialize(batch, attempt)
      @batch = batch
      @attempt = attempt
    end

    def scope
      @scope ||= self.class.scope_for(batch.season.year - 1)
    end

    def self.scope_for(year)
      memberships = TeamSeason.joins(:season).where(seasons: { year: }).order(:team_id).pluck(:team_id, :id).to_h
      TeamExternalIdentity.where(provider: 'cbbd').includes(:team).order(:external_id).map do |mapping|
        mapping_row(mapping, memberships)
      end
    end

    def self.mapping_row(mapping, memberships)
      id = mapping.team_id
      { 'provider_team_id' => PreparationForm.integer(mapping.external_id), 'team_id' => id,
        'team_name' => mapping.team.school, 'prior_team_season_id' => memberships[id] }
    end

    def proposed_attempt
      @proposed_attempt ||= DepartureAcquisition.new(departure_batch: batch, predecessor: attempt, plan:,
                                                     manifest: plan.merge(attempt.manifest.slice('sources', 'captures')),
                                                     evidence: attempt.evidence, status: 'running')
    end

    def dataset
      @dataset ||= RetainedEvidence.new(proposed_attempt).dataset
    end

    def plan
      @plan ||= base_plan.merge('expected_picks' => selections.pluck('overall_pick'), 'team_matches' => scope,
                                'scope_evidence' => { 'policy' => POLICY }, 'draft_policy' => 'confirmed_retained_results')
    end

    def selections
      source = attempt.manifest.fetch('sources').find { |entry| entry['id'] == 'draft' }
      Contract.check!(source.present? && source['failure'].blank?, 'Resolve failed draft source before publication')
      rows = CbbdSnapshot.parse(RetainedEvidence.new(attempt).bytes('draft'))
      CbbdSelections.new(rows, attempt.plan).call
    end

    def sources
      retained = RetainedEvidence.new(attempt)
      @sources ||= attempt.manifest.fetch('sources', []).map { |source| self.class.source_summary(source, retained) }
    end

    private

    attr_reader :batch, :attempt

    def base_plan
      Contract.check!(attempt&.terminal? && attempt.manifest.present?, 'Acquire sources before confirming draft teams')
      captured_plan = attempt.plan
      Contract.check!(captured_plan['target_year'] == batch.season.year, 'Departure target season mismatch')
      captured_plan.slice('draft_year', 'prior_season_year', 'target_year', 'max_requests', 'retries')
                   .merge('provider' => 'cbbd', 'schema' => CbbdDataset::VERSION,
                          'extraction_version' => CbbdDataset::AUTOMATIC_EXTRACTION)
    end

    public_class_method def self.source_summary(source, retained)
      return source.merge('row_count' => 0) if source['failure'].present?

      count = CbbdSnapshot.parse(retained.bytes(source.fetch('id'))).size
      source.merge('row_count' => count)
    rescue ArgumentError, KeyError, TypeError, JSON::ParserError => error
      source.merge('row_count' => 0, 'failure' => error.message)
    end
  end
end
