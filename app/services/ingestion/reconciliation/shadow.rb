# frozen_string_literal: true

module Ingestion
  module Reconciliation
    # Differences are evidence to investigate, never a requirement of exact parity.
    class Shadow
      def initialize(games:)
        @games = games
      end

      def call
        { 'games_compared' => eligible.size, 'fields_compared' => comparisons.size,
          'mismatch_count' => mismatches.size, 'mismatches' => mismatches }
      end

      def self.equal_values?(field)
        source, local = field.values_at('source', 'local')
        source.present? && source == local
      end

      def self.difference(attributes)
        { 'category' => 'unresolved_evidence', 'evidence' => 'Normalized source and stored local values; missing remains unknown' }
          .merge(attributes)
      end

      def self.eligible?(row)
        %w[mapped proposed].include?(row['status']) && row['candidate_ids'].one?
      end

      private

      def eligible
        @games.select { |row| Shadow.eligible?(row) }
      end

      def mismatches
        @mismatches ||= comparisons.reject { |field| Shadow.equal_values?(field) }
      end

      def comparisons
        @comparisons ||= eligible.flat_map { |row| ShadowGame.new(row).call }
      end
    end
  end
end
