# frozen_string_literal: true

module Ingestion
  module Cbbd
    # Joins source-qualified observations while preserving orphan evidence.
    class RunNormalizer
      def initialize(rows, ledger)
        @games = rows.fetch('/games')
        @boxes = rows.fetch('/games/teams').group_by { |entry| entry.dig('raw', 'gameId') }
        @ledger = ledger
      end

      def orphan_boxes
        @boxes.except(*@games.map { |entry| entry.dig('raw', 'id') }).values.flatten(1)
      end

      def call
        observations = @games.map { |game| Normalizer.new(game, @boxes.fetch(game.dig('raw', 'id'), [])).call }
        conflicts = observations.flat_map { |observation| observation['conflicts'] }
        summary(observations, conflicts, orphan_boxes)
      end

      def summary(observations, conflicts, orphans)
        { 'observations' => observations, 'acquisition' => @ledger, 'normalization_conflicts' => conflicts,
          'orphan_boxes' => orphans, 'complete' => @ledger['complete'] && conflicts.empty? && orphans.empty? }
      end
    end
  end
end
