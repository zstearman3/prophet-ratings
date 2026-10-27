# frozen_string_literal: true

module Departures
  # The existing automatic policy is proposed from authenticated source rows, never approved by acquisition.
  class EffectiveDraftPlan
    def self.applicable?(manifest)
      manifest['provider'] == 'cbbd' && (CapturePreparation.capture_only?(manifest) || CbbdDataset.automatic?(manifest) ||
        manifest['coverage_review'].present?)
    end

    def initialize(manifest, sources)
      @manifest = manifest
      @sources = sources
    end

    def call
      plan = base.merge('expected_picks' => selections.pluck('overall_pick'), 'team_matches' => team_matches,
                        'scope_evidence' => { 'policy' => DraftTeamSnapshot::POLICY }, 'draft_policy' => 'confirmed_retained_results')
      CbbdDataset.validate_plan(plan)
      plan.merge(@manifest.slice('sources', 'captures'))
    end

    private

    def base
      @manifest.slice('draft_year', 'prior_season_year', 'target_year', 'max_requests', 'retries')
               .merge('provider' => 'cbbd', 'schema' => CbbdDataset::VERSION, 'extraction_version' => CbbdDataset::AUTOMATIC_EXTRACTION)
    end

    def selections
      draft = @sources['draft']
      Contract.check!(draft&.status == 'completed', 'Resolve failed draft source before publication')
      CbbdSelections.new(draft.rows.order(:ordinal).skip_query_cache!.pluck(:fact), @manifest).call
    end

    def team_matches
      DraftTeamSnapshot.scope_for(@manifest.fetch('prior_season_year'))
    end
  end
end
