# frozen_string_literal: true

module Ingestion
  module Reconciliation
    # Aligns both score and statistical comparisons with the reviewed local sides.
    class ShadowGame
      def initialize(row)
        @game = Game.find(row.fetch('candidate_ids').first)
        @observation = row.fetch('observation')
        @reversed = row.fetch('candidates').first.fetch('reversed')
      end

      def call
        metadata + %w[home away].flat_map { |side| side_values(side) }
      end

      private

      def metadata
        values = { 'status' => [@observation['status'], @game.canceled? ? 'cancelled' : @game.status],
                   'schedule_date' => [@observation['schedule_date'], @game.schedule_date.iso8601],
                   'venue' => [@observation.dig('venue', 'certainty'), @game.venue_type] }
        values.map do |field, pair|
          Shadow.difference('local_game_id' => @game.id, 'field' => field, 'source' => pair[0], 'local' => pair[1])
        end
      end

      def side_values(side)
        local_side = @reversed ? { 'home' => 'away', 'away' => 'home' }.fetch(side) : side
        ShadowSide.new(game: @game, source: @observation.fetch(side), alignment: [side, local_side]).call
      end
    end
  end
end
