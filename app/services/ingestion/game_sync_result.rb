# frozen_string_literal: true

module Ingestion
  # Retrieval completeness and final-box coverage are independent from row acceptance.
  class GameSyncResult
    def initialize(result)
      @result = result
      @games = result.fetch(:games)
    end

    def call
      @result.merge(complete: @games.none? { |game| GameSyncProvider.held?(game) }, retrieval_complete: true,
                    valid_empty: @games.empty?, outcomes: tally(:outcome), counts:, final_box_coverage: tally(:final_box))
    end

    def self.incomplete?(game)
      game[:outcome] == 'incomplete' || game[:final_box] == 'missing'
    end

    private

    def counts
      { accepted: @games.count { |game| game[:accepted] }, protected: count_outcomes(%w[stale superseded protected]),
        rejected: count_outcomes(%w[invalid ambiguous conflict]), unmatched: count_outcomes(['unmatched']),
        incomplete: incomplete_count }
    end

    def incomplete_count
      @games.count { |game| self.class.incomplete?(game) }
    end

    def count_outcomes(values)
      @games.count { |game| values.include?(game[:outcome]) }
    end

    def tally(field)
      @games.map { |game| game.fetch(field, 'unknown') }.tally
    end
  end
end
