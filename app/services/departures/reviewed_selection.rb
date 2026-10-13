# frozen_string_literal: true

module Departures
  # Reviewed identity decisions join draft and school provider IDs, never names alone.
  class ReviewedSelection
    def initialize(selection:, decision:, dataset:, identity:)
      @selection = selection
      @decision = decision
      @dataset = dataset
      @identity = identity
    end

    def call
      return selection.merge('status' => 'unknown_participation', 'reason' => 'No reviewed decision', 'stints' => []) unless decision

      validate_decision
      stints = production_stints
      self.class.validate_stints(stints, decision)
      selection.merge(decision.slice('status', 'reason', 'evidence_source_ids', 'team_name_source', 'team_source'),
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
    end

    def production_stints
      decision.fetch('stints', []).map { |stint| ProductionStint.new(stint:, dataset:, identity:).call }
    end

    def unresolved_candidates
      return [] unless decision['team_name_source']

      identity.candidates(decision.fetch('team_name_source'), source: decision.fetch('team_source'))
    end
  end
end
