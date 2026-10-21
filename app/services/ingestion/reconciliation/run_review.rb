# frozen_string_literal: true

module Ingestion
  module Reconciliation
    # One run lock serializes refresh, draft saves and the existing atomic identity apply.
    class RunReview
      def initialize(run)
        @run = run
      end

      def compare
        locked { create_comparison(@run.verified_replay) }
      end

      def save(submission)
        locked do
          @comparison = current(submission)
          raise ArgumentError, 'This version was already applied; refresh remaining work' if comparison.identity_mapping_decision_id

          comparison.save_draft(DraftRow.collection(comparison.report, submission.fetch('rows', [])), submission)
        end
      end

      def apply(submission, reviewer:)
        locked do
          @comparison = current(submission)
          validate_application(submission)
          persist_application(submission.fetch('reason').strip, reviewer)
        end
      end

      private

      attr_reader :comparison

      def create_comparison(replay)
        report = Comparison.new(season: @run.season, replay:).call
        previous = @run.active_comparison
        version = @run.comparisons.create!(version: (previous&.version || 0) + 1, replay:, report:,
                                           artifact_digest: SeasonMembershipProposal.digest([report, replay]),
                                           draft: DraftRow.carried(previous&.draft || {}, report))
        @run.update!(active_comparison: version)
        version
      end

      def validate_application(submission)
        @run.verified_replay
        return if submission['confirm'] == '1' && submission['reason'].present?

        raise ArgumentError,
              'Explicit confirmation and reason required'
      end

      def persist_application(reason, reviewer)
        decisions = application(reason, reviewer)
        decision = Apply.new(comparison: comparison.report, replay: comparison.replay, decisions:).call
        comparison.update!(identity_mapping_decision: decision)
        decision
      end

      def locked
        CbbdReviewRun.transaction do
          CbbdReviewRun.connection.execute("SET LOCAL lock_timeout = '3s'")
          @run.lock!
          yield
        end
      rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked
        raise Apply::RetryableConflict, 'Review lock contention; transaction rolled back. Retry.'
      end

      def current(submission)
        comparison = @run.comparisons.find(submission.fetch('comparison_id'))
        raise ArgumentError, 'Comparison version changed; reopen current review' unless comparison.id == @run.active_comparison_id
        unless comparison.draft_revision.to_s == submission.fetch('draft_revision').to_s
          raise ArgumentError,
                'Draft changed; reopen and review'
        end

        comparison.verify_artifact
        comparison
      end

      def application(reason, reviewer)
        choices = comparison.selected_choices
        raise ArgumentError, 'Select at least one mapping explicitly' if choices.empty?

        { 'fingerprint' => comparison.report.fetch('fingerprint'), 'reason' => reason,
          'reviewer' => "User #{reviewer.id}: #{reviewer.email}", 'choices' => choices }
      end
    end
  end
end
