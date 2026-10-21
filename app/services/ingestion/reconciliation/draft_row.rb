# frozen_string_literal: true

module Ingestion
  module Reconciliation
    # Browser rows store intent separately from an explicit approval.
    class DraftRow
      def initialize(report, attributes)
        @report = report
        @attributes = attributes.stringify_keys
      end

      def key
        [@attributes.fetch('entity'), @attributes.fetch('external_id')].join(':')
      end

      def call
        draft = values
        validate_target(candidate, draft)
        draft
      end

      def self.collection(report, rows)
        raise ArgumentError, 'Review rows must be an array' unless rows.is_a?(Array)

        rows.to_h do |attributes|
          row = new(report, attributes)
          [row.key, row.call]
        end
      end

      def self.carried(draft, report)
        draft.filter_map do |key, value|
          hint = value.merge('selected' => '0', 'deferred' => value['deferred'] ? '1' : '0')
          [key, new(report, hint).call]
        rescue ArgumentError
          nil
        end.to_h
      end

      private

      def candidate
        entity = @attributes.fetch('entity')
        raise ArgumentError, 'Invalid entity' unless %w[team game].include?(entity)

        @report.fetch("#{entity}s").find { |row| row['external_id'] == @attributes.fetch('external_id') } ||
          raise(ArgumentError, 'Unknown source identity')
      end

      def choice
        value = @attributes.slice('entity', 'external_id')
        previous = @attributes['supersedes_external_id']
        value['supersedes_external_id'] = previous if previous.present?
        value
      end

      def local_id
        target = @attributes['local_id']
        Integer(target.to_s, 10) if target.present?
      end

      def values
        value = choice
        value['local_id'] = local_id
        value['action'] = @attributes.fetch('action', 'associate')
        value.merge('selected' => @attributes['selected'] == '1', 'deferred' => @attributes['deferred'] == '1')
      end

      def validate_target(row, draft)
        target = draft['local_id']
        eligible = row.fetch('eligible_ids', row.fetch('candidate_ids'))
        raise ArgumentError, 'Target is not a reviewed candidate' if target && eligible.exclude?(target)
        raise ArgumentError, 'Invalid action' unless %w[associate supersede].include?(draft['action'])

        validate_approval(row, draft) if draft['selected']
      end

      def validate_approval(row, draft)
        raise ArgumentError, 'Conflicting or deferred evidence cannot be approved' if row['status'] == 'conflicting' || draft['deferred']
        raise ArgumentError, 'Choose a reviewed candidate' unless draft['local_id']
      end
    end
  end
end
