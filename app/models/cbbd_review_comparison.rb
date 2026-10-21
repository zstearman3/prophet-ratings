# frozen_string_literal: true

# Exact report/replay versions survive draft editing and identity application.
class CbbdReviewComparison < ApplicationRecord
  belongs_to :cbbd_review_run
  belongs_to :identity_mapping_decision, optional: true
  before_update :preserve_artifact
  before_update :preserve_application
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'CBBD comparisons are immutable' }

  def verify_artifact
    return if artifact_digest == SeasonMembershipProposal.digest([report, replay])

    raise Ingestion::Cbbd::CaptureStore::IntegrityError, 'Stored comparison changed'
  end

  def save_draft(rows, submission)
    merged = draft.merge(rows)
    merged = Ingestion::Reconciliation::BulkApproval.new(report, merged, submission).call if submission['bulk'] == '1'
    update!(draft: merged, draft_revision: draft_revision + 1)
    self
  end

  def selected_choices
    draft.values.select { |row| self.class.approved?(row) }.map { |row| row.except('selected', 'deferred') }
  end

  def self.approved?(row)
    row['selected'] && !row['deferred']
  end

  private

  def preserve_application
    return unless identity_mapping_decision_id_in_database
    return unless %w[draft draft_revision identity_mapping_decision_id].any? { |field| will_save_change_to_attribute?(field) }

    raise ActiveRecord::ReadOnlyRecord, 'Applied CBBD drafts and decisions are immutable'
  end

  def preserve_artifact
    return unless %w[report replay artifact_digest version cbbd_review_run_id].any? { |field| will_save_change_to_attribute?(field) }

    raise ActiveRecord::ReadOnlyRecord, 'CBBD comparison artifacts are immutable'
  end
end
