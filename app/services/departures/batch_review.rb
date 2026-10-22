# frozen_string_literal: true

module Departures
  # Draft review is resumable; only explicit approval publishes existing input contracts.
  class BatchReview
    def initialize(batch)
      @batch = batch
    end

    def dataset(attempt: batch.attempt)
      Contract.check!(attempt.present?, 'Acquire usable evidence before reviewing decisions')
      RetainedEvidence.new(attempt).verified_dataset(batch.plan)
    end

    def report(attempt: batch.attempt)
      facts = dataset(attempt:)
      result = Preview.new(dataset: facts, review: draft_document(facts)).call
      result.merge('gaps' => CoverageGaps.new(facts, result, batch.season.team_seasons.pluck(:team_id)).call, 'errors' => [])
    rescue ArgumentError, KeyError => error
      { 'selections' => attempt&.dataset&.fetch('selections', []) || [], 'teams' => [],
        'gaps' => [], 'errors' => [error.message] }
    end

    def review_key(attempt: batch.attempt)
      latest_id = OffseasonInputRevision.where(season_id: batch.season_id, kind: 'departures').maximum(:id)
      Contract.digest([batch.attributes, attempt&.attributes, Team.order(:id).pluck(:id, :school),
                       TeamAlias.order(:id).map(&:attributes), TeamExternalIdentity.order(:id).map(&:attributes), profile_state, latest_id])
    end

    def save(attributes)
      guarded do
        validate_draft(attributes)
        decisions = DecisionForm.new(dataset).call(attributes.fetch('rows', {}))
        batch.update!(decisions:, acknowledgement: {})
      end
    end

    def publish(attributes, reviewer:)
      guarded do
        return batch.revision if batch.status == 'published'

        validate_draft(attributes)
        approve(attributes, reviewer)
        publish_inputs
      end
    end

    def document
      draft_document(dataset).merge('reviewed_by' => batch.reviewed_by, 'reviewed_at' => batch.reviewed_at.iso8601(6),
                                    'partial_acknowledgement' => batch.acknowledgement)
    end

    private

    attr_reader :batch

    def guarded
      Season.with_ratings_lock do
        batch.season.with_lock do
          batch.with_lock do
            self.class.lock_provider_mappings if batch.plan['provider'] == 'cbbd'
            yield
          end
        end
      end
    end

    public_class_method def self.lock_provider_mappings
      # Pin both present and absent mappings through review and publication.
      TeamExternalIdentity.connection.execute('LOCK TABLE team_external_identities IN SHARE MODE')
    end

    def validate_draft(attributes)
      batch.require_editable
      Contract.check!(attributes['review_key'] == review_key, 'Departure review changed; reload and review again')
    end

    def profile_state
      batch.season.team_seasons.includes(:team_offseason_profile).order(:id).map do |row|
        OffseasonInputs::Import.profile_before(row)
      end
    end

    def draft_document(facts)
      { 'dataset_revision' => facts.fetch('dataset_revision'), 'decisions' => batch.decisions,
        'revision_id' => "departure-batch-#{batch.id}", 'decision' => 'approved',
        'reviewed_by' => 'Draft calculation only; not approved', 'reviewed_at' => batch.created_at.iso8601(6),
        'partial_acknowledgement' => batch.acknowledgement }
    end

    def approve(attributes, reviewer)
      Contract.check!(attributes['confirm'] == '1', 'Confirm explicit approval of the saved decisions')
      Contract.text!(reviewer, 'authenticated reviewer')
      current = checked_report
      acknowledgement = CoverageGaps.acknowledgement(current.fetch('gaps'), attributes, reviewer)
      batch.update!(reviewed_by: reviewer, reviewed_at: Time.current, acknowledgement:)
    end

    def publish_inputs
      RetainedEvidence.new(batch.attempt).publish(document, batch.season) { |payload| publication_metadata(payload) }
      batch.update!(status: 'published', revision: batch.latest_revision)
      batch.revision
    end

    def checked_report
      current = report
      errors = current.fetch('errors')
      self.class.validate_errors(errors)
      current
    end

    public_class_method def self.validate_errors(errors)
      Contract.check!(errors.empty?, errors.join('; '))
    end

    def publication_metadata(payload)
      { version: "departure-batch-#{batch.id}", reason: batch.correction_reason.presence || 'Manual departure review',
        predecessor_id: batch.latest_revision&.id, input_hash: Contract.digest(payload) }
    end
  end
end
