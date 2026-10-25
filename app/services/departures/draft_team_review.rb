# frozen_string_literal: true

module Departures
  # One operator confirmation publishes a frozen draft-to-college projection from retained sources.
  class DraftTeamReview
    def initialize(batch, attempt: batch.attempt)
      @batch = batch
      @attempt = attempt
      @snapshot = DraftTeamSnapshot.new(batch, attempt)
    end

    def self.applicable?(batch)
      plan = batch.plan
      return false unless plan['provider'] == 'cbbd'
      return true if CbbdDataset.automatic?(plan)

      batch.status == 'draft' && (CapturePreparation.capture_only?(plan) || plan['coverage_review'].present?)
    end

    def report
      @report ||= batch.status == 'published' ? published_report : proposed_report
    rescue ArgumentError, KeyError, TypeError, JSON::ParserError => error
      { 'players' => [], 'teams' => [], 'sources' => snapshot.sources, 'production_warnings' => [],
        'review_key' => review_key, 'errors' => [error.message] }
    end

    def review_key
      Contract.digest([CbbdDataset::AUTOMATIC_EXTRACTION, BatchReview.new(batch).review_key(attempt:), snapshot.scope])
    end

    def publish(attributes, reviewer:)
      return batch.revision if batch.status == 'published'

      self.class.confirm(attributes, reviewer)
      BatchReview.new(batch).publish({}, reviewer:) { prepare_current(attributes) }.tap { @report = nil }
    end

    def self.confirm(attributes, reviewer)
      Contract.check!(attributes['confirm'] == '1', 'Confirm the draft results and college teams')
      Contract.text!(reviewer, 'authenticated reviewer')
    end

    def prepare(attributes)
      Contract.check!(attributes['review_key'] == review_key, 'Departure draft/team review changed; reload and confirm again')
      BatchReview.validate_errors(report.fetch('errors'))
      persist_proposal
      { 'review_key' => BatchReview.new(batch).review_key, 'confirm' => '1' }
    end

    private

    attr_reader :batch, :attempt, :snapshot

    def prepare_current(attributes)
      TeamSeason.connection.execute('LOCK TABLE team_seasons IN SHARE MODE')
      self.class.new(batch).prepare(attributes)
    end

    def persist_proposal
      attributes = snapshot.proposed_attempt.attributes.except('id', 'created_at', 'updated_at').merge('started_at' => Time.current)
      successor = batch.acquisitions.create!(attributes)
      BatchAcquisition.new(successor).finish
      batch.update!(plan: successor.plan, decisions: decisions, acknowledgement: {}, reviewed_by: nil, reviewed_at: nil)
    end

    def facts
      snapshot.dataset
    end

    def decisions
      @decisions ||= DraftTeamMatches.new(facts).call
    end

    def require_applicable
      Contract.check!(self.class.applicable?(batch), 'This departure batch uses the existing review workflow')
    end

    def proposed_report
      require_applicable
      document = { 'dataset_revision' => facts.fetch('dataset_revision'), 'revision_id' => "departure-batch-#{batch.id}",
                   'decision' => 'approved', 'reviewed_by' => 'Unpublished draft/team proposal',
                   'reviewed_at' => batch.created_at.iso8601(6), 'decisions' => decisions }
      preview = Preview.new(dataset: facts, review: document).call
      self.class.present(facts, preview, snapshot.sources).merge('review_key' => review_key,
                                                                 'errors' => facts.fetch('failures').pluck('failure'))
    end

    def published_report
      payload = batch.revision.payload
      self.class.present(payload.fetch('dataset'), payload.fetch('report'), snapshot.sources).merge('review_key' => nil, 'errors' => [])
    end

    public_class_method def self.present(dataset, preview, sources)
      { 'players' => DraftTeamMatches.present(preview.fetch('selections'), dataset), 'teams' => preview.fetch('teams'),
        'sources' => sources, 'production_warnings' => dataset.fetch('production_warnings', []) }
    end
  end
end
