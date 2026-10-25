# frozen_string_literal: true

module Departures
  # Reviewed identity decisions join draft and school provider IDs, never names alone.
  class ReviewedSelection
    def initialize(selection:, decision:, dataset:, identity:)
      @selection = CbbdDataset.automatic?(dataset) ? DraftTeamMatches.resolve(selection, dataset) : selection
      @decision = decision
      @dataset = dataset
      @identity = identity
    end

    def call
      return selection.merge('status' => 'unknown_participation', 'reason' => 'No reviewed decision', 'stints' => []) unless decision

      validate_decision
      stints = production_stints
      validate_production(stints)
      selection.merge(decision.slice('status', 'reason', 'evidence_source_ids', 'team_name_source', 'team_source',
                                     'unknown_team_ids', 'matched_provider_athlete_id', 'match_method'),
                      'candidate_team_ids' => unresolved_candidates, 'stints' => stints)
    end

    def self.evidence(ids, dataset)
      Contract.check!(ids.is_a?(Array) && ids.any?, 'Require captured participation/player identity evidence')
      available = dataset.fetch('sources').reject { |source| source['failure'] }.pluck('id') - dataset.fetch('failures').pluck('id')
      Contract.check!((ids - available).empty?, 'Evidence source missing or failed')
    end

    def self.validate_stints(stints, decision)
      status = decision.fetch('status')
      Contract.unique!(stints.pluck('team_id'), 'team stints within one selection')
      Contract.check!(status != 'eligible_prior_season' || stints.any?, 'Eligible selection requires production stints')
      Contract.check!(status == 'eligible_prior_season' || stints.empty?, 'Only eligible selections may supply production')
    end

    private

    attr_reader :selection, :decision, :dataset, :identity

    def validate_decision
      Contract.check!(Contract::STATUSES.include?(decision.fetch('status')), 'Invalid accounting status')
      Contract.text!(decision.fetch('reason'), 'decision reason')
      self.class.evidence(decision.fetch('evidence_source_ids'), dataset)
      DraftTeamMatches.validate_decision(selection, decision, dataset)
    end

    def automatic?
      CbbdDataset.automatic?(dataset)
    end

    def production_stints
      decision.fetch('stints', []).map { |stint| ProductionStint.new(stint:, dataset:, identity:).call }
    end

    def validate_production(stints)
      self.class.validate_stints(stints, decision)
      validate_provider(stints) if dataset['provider']
    end

    def validate_provider(stints)
      status = decision.fetch('status')
      self.class.validate_exclusion(status, dataset:)
      return unless status == 'eligible_prior_season'

      validate_provider_stints(stints)
    end

    def validate_provider_stints(stints)
      key = PlayerIdentity.key(selection)
      self.class.validate_athlete(stints, key)
      return if automatic?

      expected = provider_tables(key).pluck('production_key').sort
      Contract.check!(stints.pluck('production_key').sort == expected, 'Review all evidenced athlete team stints')
    end

    def provider_tables(key)
      dataset.fetch('production').select { |table| self.class.athlete_table?(table, key) }
    end

    public_class_method def self.validate_exclusion(status, dataset: {})
      return if CbbdDataset.automatic?(dataset) && status == 'outside_prior_season'

      return unless Contract::RESOLVED.include?(status) && status != 'eligible_prior_season'

      raise ArgumentError, 'CBBD absence/affiliation does not prove an exclusion; keep participation unknown'
    end

    public_class_method def self.validate_athlete(stints, key)
      Contract.check!(stints.all? { |stint| PlayerIdentity.key(stint) == key }, 'Wrong provider athlete for draft selection')
    end

    public_class_method def self.athlete_table?(table, key)
      table.fetch('players').any? { |player| PlayerIdentity.key(player) == key }
    end

    def provider_candidates
      return DraftTeamMatches.candidate_team_ids(selection, dataset) if automatic?
      return [] unless selection['provider_athlete_id']

      tables = provider_tables(PlayerIdentity.key(selection))
      return [] if tables.empty?

      self.class.mapped_candidates((tables.pluck('provider_team_id') + [selection['provider_team_id']]).compact.uniq)
    end

    public_class_method def self.mapped_candidates(provider_ids)
      candidates = provider_ids.map { |id| PlayerIdentity.team_candidates(id) }
      candidates.all?(&:one?) ? candidates.flatten.uniq.sort : []
    end

    def unresolved_candidates
      return provider_candidates if dataset['provider']
      return [] unless decision['team_name_source']

      identity.candidates(decision.fetch('team_name_source'), source: decision.fetch('team_source'))
    end
  end
end
