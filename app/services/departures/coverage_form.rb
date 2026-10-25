# frozen_string_literal: true

module Departures
  # Authenticated approval is separate from both provider observations and downstream player decisions.
  class CoverageForm
    def initialize(batch, attributes, reviewer:, attempt:)
      @batch = batch
      @attributes = attributes
      @reviewer = reviewer
      @attempt = attempt
    end

    attr_reader :attempt

    def review_key
      attributes['review_key']
    end

    def call(allowed_absences)
      validate_confirmation
      plan = PreparationForm.new(form_fields, batch.season).call
      Contract.check!((plan.fetch('absent_postseason_team_ids') - allowed_absences).empty?, 'Unverified no-postseason team selection')
      plan.merge('extraction_version' => CbbdDataset::REPORTED_TOTALS_EXTRACTION, 'coverage_review' => provenance)
    end

    private

    attr_reader :batch, :attributes, :reviewer

    def form_fields
      attempt.plan.slice('draft_year', 'prior_season_year', 'target_year', 'max_requests', 'retries')
             .merge(attributes.slice('expected_picks', 'scope_evidence'), 'absent_postseason_team_ids' => absence_ids)
    end

    def absence_ids
      self.class.parse_absence_ids(attributes.fetch('absent_postseason_team_ids', []))
    end

    public_class_method def self.parse_absence_ids(value)
      value.is_a?(Array) ? value.compact_blank.join(' ') : value
    end

    def validate_confirmation
      Contract.text!(reviewer, 'authenticated coverage reviewer')
      Contract.check!(attributes['confirm_picks'] == '1', 'Confirm picks against independent final draft results')
      Contract.text!(attributes.fetch('picks_evidence'), 'independent final draft evidence')
      Contract.check!(attributes['confirm_scope'] == '1', 'Confirm completed regular and postseason scope')
    end

    def provenance
      { 'reviewed_by' => reviewer, 'reviewed_at' => Time.current.iso8601(6), 'predecessor_id' => attempt.id,
        'picks_evidence' => attributes.fetch('picks_evidence'), 'scope_evidence' => attributes.fetch('scope_evidence') }
    end
  end
end
