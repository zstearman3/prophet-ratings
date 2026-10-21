# frozen_string_literal: true

module Ingestion
  module Reconciliation
    # Ordered membership, schedule and venue evidence for one local candidate.
    class CandidateEvidence
      def initialize(game:, observation:, source_pair:)
        @game = game
        @observation = observation
        @participants = LocalEvidence.participants(game)
        @alignment = align(source_pair)
      end

      def to_h
        { 'local_id' => @game.id, 'home_ids' => @participants.first, 'away_ids' => @participants.last, 'schedule_date' => date,
          'start_time' => @game.start_time.iso8601, 'venue_type' => @game.venue_type, 'venue_confidence' => @game.venue_confidence,
          'rules' => rules, 'reversed' => @alignment == 'reversed', 'alignment' => @alignment }
      end

      private

      def align(source_pair)
        direct = aligned?(source_pair)
        reverse = aligned?(source_pair.reverse)
        return 'ambiguous' if direct && reverse

        reverse ? 'reversed' : 'ordered'
      end

      def aligned?(source_pair)
        @participants.zip(source_pair).all? { |local, source| local.intersect?(source) }
      end

      def date
        @game.schedule_date.iso8601
      end

      def rules
        orientation_rules + date_rules + (@game.venue_confidence == 'manual' ? ['manual_venue'] : [])
      end

      def orientation_rules
        return [] unless @alignment == 'reversed'

        @observation.dig('venue', 'certainty') == 'neutral' ? ['reversed_sides'] : %w[reversed_sides non_neutral_orientation_review]
      end

      def date_rules
        source_date = @observation['schedule_date']
        return [] if date == source_date

        @game.start_time.utc.to_date.iso8601 == source_date ? %w[possible_reschedule legacy_date_shift] : ['possible_reschedule']
      end
    end
  end
end
