# frozen_string_literal: true

module Ingestion
  module Reconciliation
    # Validates the whole batch before writes, using an order-independent participant map.
    class Selection
      def initialize(comparison:, decisions:)
        @comparison = comparison
        @decisions = decisions
      end

      def call
        validate_request
        choices.map do |choice|
          reviewed = ReviewedChoice.new(choice:, comparison: @comparison, teams: effective_teams)
          reviewed.validate
          reviewed
        end
      end

      def self.team_pair(choice)
        raise ArgumentError, 'Choice must be an object' unless choice.is_a?(Hash)

        choice.values_at('external_id', 'local_id') if choice['entity'] == 'team'
      end

      private

      def choices
        @decisions.fetch('choices')
      end

      def validate_request
        raise ArgumentError, 'Unknown decision keys' if (@decisions.keys - %w[fingerprint reviewer reason choices]).any?
        raise ArgumentError, 'Reviewer and reason required' if @decisions.values_at('reviewer', 'reason').any?(&:blank?)
        raise ArgumentError, 'Fingerprint does not match artifact' unless @decisions['fingerprint'] == @comparison['fingerprint']
        raise ArgumentError, 'Choices must be an array' unless @decisions['choices'].is_a?(Array)

        validate_unique
      end

      def validate_unique
        keys = choices.map do |choice|
          raise ArgumentError, 'Choice must be an object' unless choice.is_a?(Hash)

          choice.values_at('entity', 'external_id')
        end
        raise ArgumentError, 'Duplicate source choice' unless keys.uniq == keys

        validate_game_targets
      end

      def validate_game_targets
        targets = choices.select { |choice| choice['entity'] == 'game' }.pluck('local_id')
        raise ArgumentError, 'Choose one source game authority per local target in a batch' unless targets.uniq == targets
      end

      def effective_teams
        @effective_teams ||= TeamExternalIdentity.where(provider: 'cbbd').pluck(:external_id, :team_id).to_h.merge(selected_teams)
      end

      def selected_teams
        choices.filter_map { |choice| Selection.team_pair(choice) }.to_h
      end
    end
  end
end
