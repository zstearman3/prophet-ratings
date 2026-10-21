# frozen_string_literal: true

module Ingestion
  module Cbbd
    # Maps official team totals only; mirrored totals never fill authoritative gaps.
    class BoxNormalizer
      PATHS = {
        'field_goals_made' => %w[fieldGoals made], 'field_goals_attempted' => %w[fieldGoals attempted],
        'two_pt_made' => %w[twoPointFieldGoals made], 'two_pt_attempted' => %w[twoPointFieldGoals attempted],
        'three_pt_made' => %w[threePointFieldGoals made], 'three_pt_attempted' => %w[threePointFieldGoals attempted],
        'free_throws_made' => %w[freeThrows made], 'free_throws_attempted' => %w[freeThrows attempted],
        'offensive_rebounds' => %w[rebounds offensive], 'defensive_rebounds' => %w[rebounds defensive],
        'rebounds' => %w[rebounds total], 'turnovers' => %w[turnovers total], 'fouls' => %w[fouls total],
        'points' => %w[points total], 'assists' => %w[assists], 'blocks' => %w[blocks], 'steals' => %w[steals]
      }.freeze

      def initialize(row)
        @row = row
      end

      def call
        stats = PATHS.to_h { |name, path| [name, StatField.new(@row, ['teamStats', *path]).call] }
        stats.merge('minutes' => minutes)
      end

      def minutes
        duration = StatField.new(@row, ['gameMinutes']).call
        duration.merge('units' => 'summed_player_minutes', 'derivation' => 'gameMinutes * 5',
                       'value' => duration_value)
      end

      def duration_value
        StatField.new(@row, ['gameMinutes']).call['value']&.*(5)
      end

      def mirror
        PATHS.to_h { |name, path| [name, StatField.new(@row, ['opponentStats', *path]).call] }
      end
    end
  end
end
