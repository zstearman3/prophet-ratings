# frozen_string_literal: true

module Ingestion
  module Reconciliation
    # Only the explicitly submitted visible proposed rows can receive bulk approval.
    class BulkApproval
      def initialize(report, draft, submission)
        @report = report
        @draft = draft
        @visible = submission.fetch('rows', []).map { |row| DraftRow.new(report, row).key }
        @page = ReviewPage.new(report, submission.fetch('filters', {}))
      end

      def call
        validate_visible
        @draft.each do |key, value|
          approve(value) if @visible.include?(key)
        end
        validate_selection
        @draft
      end

      def self.approve_proposal(row, value)
        targets = row.fetch('eligible_ids', row.fetch('candidate_ids'))
        return unless row['status'] == 'proposed' && targets.one? && !value['deferred']

        value.merge!('local_id' => targets.first, 'selected' => true)
      end

      private

      def validate_visible
        entity = @page.entity
        raise ArgumentError, 'Shadow evidence cannot be approved' if entity == 'shadow'

        allowed = @page.rows.map { |row| "#{entity}:#{row.fetch('external_id')}" }
        raise ArgumentError, 'Bulk approval must contain only visible rows' if (@visible - allowed).any?
      end

      def approve(value)
        row = @report.fetch("#{value.fetch('entity')}s").find { |candidate| candidate['external_id'] == value['external_id'] }
        self.class.approve_proposal(row, value)
      end

      def validate_selection
        selected = @draft.values.select { |value| CbbdReviewComparison.approved?(value) }
        decisions = { 'fingerprint' => @report.fetch('fingerprint'), 'reviewer' => 'bulk draft validation',
                      'reason' => 'Explicit bulk draft', 'choices' => selected.map { |value| value.except('selected', 'deferred') } }
        Selection.new(comparison: @report, decisions:).call
      end
    end
  end
end
