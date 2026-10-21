# frozen_string_literal: true

module Ingestion
  module Cbbd
    # Checks schedule/box orientation, mirrored totals and period duration evidence.
    class GameConsistency
      def initialize(game, boxes, sides)
        @game = game
        @boxes = boxes
        @sides = sides
      end

      def conflicts
        @boxes.flat_map { |entry| box_conflicts(entry['raw']) + mirror_conflicts(entry) }
      end

      def numeric_reasons
        reasons = minutes.uniq.length > 1 ? ['side minutes disagree'] : []
        reasons + %w[home away].each_with_index.flat_map { |label, index| period_reasons(label, index) }
      end

      def self.validate_periods(periods, facts)
        reasons = []
        reasons << 'period duration disagreement' unless facts.fetch(:minutes) == (40 + ((periods.size - 2) * 5)) * 5
        reasons << 'period score disagreement' unless valid_periods?(periods) && periods.sum == facts.fetch(:score)
        reasons
      end

      def self.valid_periods?(periods)
        periods.all? { |points| points.is_a?(Integer) && points >= 0 }
      end

      def self.disagreeing_fields(box, other)
        authoritative = BoxNormalizer.new(other).call
        BoxNormalizer.new(box).mirror.filter_map do |field, mirror|
          value = mirror['value']
          next unless mirror['reason'] == 'invalid_nonnegative_integer' || (value && value != authoritative.fetch(field)['value'])

          field
        end
      end

      private

      def minutes
        @sides.map { |side| side.dig('stats', 'minutes', 'value') }
      end

      def period_reasons(label, index)
        periods = @game["#{label}PeriodPoints"]
        return [] unless periods.is_a?(Array) && periods.any?

        self.class.validate_periods(periods, { minutes: minutes[index], score: @sides[index].dig('score', 'value') }).map do |reason|
          "#{label} #{reason}"
        end
      end

      def box_conflicts(box)
        expected = expected_metadata(box)
        expected.filter_map { |field, value| "box metadata conflict: #{field}" unless box[field] == value }
      end

      def expected_metadata(box)
        home = box['teamId'] == @game['homeTeamId']
        label, opponent = home ? %w[home away] : %w[away home]
        { 'gameId' => @game['id'], 'season' => @game['season'], 'teamId' => @game["#{label}TeamId"],
          'opponentId' => @game["#{opponent}TeamId"], 'isHome' => home, 'startDate' => @game['startDate'] }
          .merge(@game.slice(*box.keys.intersection(%w[neutralSite startTimeTbd status])))
      end

      def mirror_conflicts(entry)
        box = entry.fetch('raw')
        other = @boxes.find { |candidate| candidate.dig('raw', 'teamId') == box['opponentId'] }
        return [] unless other

        mirror_messages(entry, other)
      end

      def mirror_messages(entry, other)
        self.class.disagreeing_fields(entry.fetch('raw'), other.fetch('raw')).map do |field|
          "mirror conflict: #{field} (#{entry.dig('provenance', 'id')}, #{other.dig('provenance', 'id')})"
        end
      end
    end
  end
end
