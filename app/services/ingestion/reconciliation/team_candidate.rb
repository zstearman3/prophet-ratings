# frozen_string_literal: true

module Ingestion
  module Reconciliation
    # One provider team's exact evidence and membership eligibility.
    class TeamCandidate
      def initialize(season, external_id, sides, grouped)
        @input = { season:, external_id:, sides:, grouped: }
        @identity = TeamExternalIdentity.find_by(provider: 'cbbd', external_id:)
      end

      def to_h
        { 'external_id' => @input.fetch(:external_id), 'names' => names, 'candidate_ids' => candidates, 'eligible_ids' => eligible,
          'mapped_id' => @identity&.team_id, 'status' => status, 'rule' => rule, 'occurrences' => @input.fetch(:sides).size }
      end

      private

      def candidates
        @candidates ||= @identity ? [@identity.team_id] : label_candidates
      end

      def label_candidates
        names.flat_map { |name| Team.matching_school_or_alias(name).ids }.uniq.sort
      end

      def eligible
        @eligible ||= TeamSeason.where(season: @input.fetch(:season), team_id: candidates).order(:team_id).pluck(:team_id)
      end

      def rule
        @identity&.provider == 'cbbd' ? 'stable_provider_identity' : 'exact_school_or_alias'
      end

      def names
        @input.fetch(:sides).pluck('source_name').uniq
      end

      def status
        return 'conflicting' if invalid_evidence?
        return 'mapped' if @identity
        return 'unmatched' if candidates.empty?

        candidates.one? ? 'proposed' : 'ambiguous'
      end

      def invalid_evidence?
        @input.fetch(:external_id).blank? || eligible != candidates || (!@identity && (names.size != 1 || colliding_names?))
      end

      def colliding_names?
        @input.fetch(:grouped).except(@input.fetch(:external_id)).values.flatten.pluck('source_name').intersect?(names)
      end
    end
  end
end
