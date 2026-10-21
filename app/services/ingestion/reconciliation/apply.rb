# frozen_string_literal: true

module Ingestion
  module Reconciliation
    # Only reviewed identity rows and their immutable audit record are written.
    class Apply
      # Bounded database contention; the transaction has already rolled back.
      class RetryableConflict < StandardError; end

      def initialize(comparison:, replay:, decisions:)
        @comparison = comparison.deep_stringify_keys
        @replay = replay
        @decisions = decisions.deep_stringify_keys
      end

      def call
        IdentityMappingDecision.transaction do
          Apply.lock_tables
          apply_locked
        end
      rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked
        raise RetryableConflict, 'Reconciliation lock contention; transaction rolled back. Retry or recompare.'
      end

      # Literal, fixed-order table locks cover every fingerprint read table and the audit.
      LOCK_STATEMENTS = [
        'LOCK TABLE game_external_identities IN SHARE ROW EXCLUSIVE MODE',
        'LOCK TABLE games IN SHARE MODE',
        'LOCK TABLE identity_mapping_decisions IN SHARE ROW EXCLUSIVE MODE',
        'LOCK TABLE seasons IN SHARE MODE',
        'LOCK TABLE team_aliases IN SHARE MODE',
        'LOCK TABLE team_external_identities IN SHARE ROW EXCLUSIVE MODE',
        'LOCK TABLE team_games IN SHARE MODE',
        'LOCK TABLE team_seasons IN SHARE MODE',
        'LOCK TABLE teams IN SHARE MODE'
      ].freeze

      def self.lock_tables
        connection = IdentityMappingDecision.connection
        connection.execute("SET LOCAL lock_timeout = '3s'")
        LOCK_STATEMENTS.each { |statement| connection.execute(statement) }
      end

      private

      def current_comparison
        Comparison.new(season: Season.find(@comparison.fetch('season_id')), replay: @replay).call
      end

      def apply_locked
        recorded = IdentityMappingDecision.find_by(request_digest: request_digest)
        return repeat(recorded, current_comparison) if recorded

        current = current_comparison
        raise ArgumentError, 'Comparison changed; recompare and review again' unless current == @comparison

        persist_decision(current)
      end

      def request
        { 'comparison' => @comparison, 'decisions' => @decisions }
      end

      def request_digest
        @request_digest ||= SeasonMembershipProposal.digest(request)
      end

      def persist_decision(current)
        choices = Selection.new(comparison: current, decisions: @decisions).call
        results = choices.map(&:apply)
        IdentityMappingDecision.create!(request_digest: request_digest, comparison_fingerprint: current.fetch('fingerprint'),
                                        post_apply_fingerprint: current_comparison.fetch('fingerprint'),
                                        reviewer: @decisions.fetch('reviewer'), reason: @decisions.fetch('reason'),
                                        request: request, result: { 'mappings' => results })
      end

      def repeat(recorded, current)
        unless recorded.post_apply_fingerprint == current.fetch('fingerprint')
          raise ArgumentError, 'Recorded decision state changed; recompare and review again'
        end

        recorded
      end
    end
  end
end
