# frozen_string_literal: true

module Departures
  # Explicit coverage creates a new strict dataset by replaying unchanged private captures offline.
  class CoverageReview
    def initialize(batch)
      @batch = batch
    end

    def report(attempt: batch.attempt)
      key = review_key(attempt:)
      require_evidence(attempt)
      CoverageEvidence.new(attempt).call.merge('review_key' => key, 'fields' => fields)
    rescue ArgumentError, KeyError, TypeError => error
      { 'selections' => [], 'sources' => [], 'no_postseason_teams' => [], 'production_warnings' => [], 'review_key' => key,
        'fields' => fields, 'errors' => [error.message] }
    end

    def save(attributes, reviewer:)
      Season.with_ratings_lock do
        batch.season.with_lock do
          batch.with_lock do
            BatchReview.lock_provider_mappings
            finalize(CoverageForm.new(batch, attributes, reviewer:, attempt: batch.attempt))
          end
        end
      end
    end

    def review_key(attempt: batch.attempt)
      Contract.digest([CbbdDataset::REPORTED_TOTALS_EXTRACTION, batch.attributes, attempt&.attributes, Team.order(:id).pluck(:id, :school),
                       TeamExternalIdentity.order(:id).map(&:attributes)])
    end

    private

    attr_reader :batch

    def require_evidence(attempt)
      Contract.check!(attempt&.terminal? && attempt.manifest.present?, 'Acquire retained sources before coverage review')
      Contract.check!(batch.plan['provider'] == 'cbbd', 'Legacy coverage remains read-only')
    end

    def fields
      self.class.form_fields(batch.plan)
    end

    public_class_method def self.form_fields(plan)
      { 'expected_picks' => plan.fetch('expected_picks', []).join(' '),
        'scope_evidence' => plan.fetch('scope_evidence', ''),
        'picks_evidence' => plan.fetch('coverage_review', {}).fetch('picks_evidence', ''),
        'absent_postseason_team_ids' => plan.fetch('absent_postseason_team_ids', []),
        'confirm_picks' => '', 'confirm_scope' => '' }
    end

    def finalize(form)
      attempt = form.attempt
      batch.require_editable
      require_evidence(attempt)
      Contract.check!(form.review_key == review_key(attempt:), 'Departure coverage changed; reload and review again')
      finalize_review(form, report(attempt:))
    end

    def finalize_review(form, current)
      BatchReview.validate_errors(current.fetch('errors'))
      plan = form.call(current.fetch('no_postseason_teams').pluck('provider_team_id'))
      successor = replay(plan, form.attempt)
      batch.update!(plan:, decisions: [], acknowledgement: {}, reviewed_by: nil, reviewed_at: nil)
      successor
    end

    def replay(plan, original)
      successor = batch.acquisitions.create!(self.class.successor_attributes(plan, original))
      BatchAcquisition.new(successor).finish
      successor
    end

    public_class_method def self.successor_attributes(plan, original)
      manifest = plan.merge(original.manifest.slice('sources', 'captures'))
      { plan:, manifest:, evidence: original.evidence, predecessor: original, status: 'running', started_at: Time.current }
    end
  end
end
