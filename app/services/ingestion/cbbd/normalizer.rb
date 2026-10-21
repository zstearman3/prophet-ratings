# frozen_string_literal: true

module Ingestion
  module Cbbd
    # Produces provider-neutral observations without guessing any internal identities.
    class Normalizer
      STATUSES = %w[scheduled in_progress final postponed cancelled].index_with(&:itself).merge('canceled' => 'cancelled',
                                                                                                'in_progress' => 'live').freeze

      def initialize(game, boxes)
        @entry = game
        @game = game.fetch('raw')
        @boxes = boxes
        @sides = %w[home away].map { |label| side(label) }
      end

      def call
        consistency = GameConsistency.new(@game, @boxes, @sides)
        base.merge(SourceTime.new(@game).to_h).merge(validation(consistency))
      end

      private

      def validation(consistency)
        conflicts = consistency.conflicts
        reasons = numeric_reasons + consistency.numeric_reasons + conflicts
        completed = source_completed?
        { 'home' => @sides[0], 'away' => @sides[1], 'source_completed' => completed,
          'completion_evidence' => completed ? 'literal_final_unequal_scores' : nil,
          'numeric_valid' => reasons.empty?, 'reasons' => reasons, 'conflicts' => conflicts }
      end

      def numeric_reasons
        reasons = @sides.flat_map { |team| BoxValidator.new(team).call }
        reasons << 'source not confirmed final with unequal valid scores' unless source_completed?
        reasons
      end

      def base
        raw_status = @game['status']
        neutral = @game['neutralSite']
        { 'format' => CanonicalObservation::FORMAT, 'semantic_profile' => CanonicalObservation::SEMANTIC_PROFILE,
          'normalization_version' => CanonicalObservation::NORMALIZATION_VERSION, 'provider' => 'cbbd',
          'source_game_id' => @game['id'], 'season' => @game['season'], 'raw_status' => raw_status,
          'status' => canonical_status, 'model_eligible' => false,
          'venue' => { 'certainty' => neutral == true ? 'neutral' : 'unknown',
                       'raw_neutral_site' => neutral, 'name' => @game['venue'] },
          'provenance' => [@entry['provenance'], *@boxes.pluck('provenance')] }
      end

      def side(label)
        id = @game["#{label}TeamId"]
        box = @boxes.find { |entry| entry['raw']['teamId'] == id }
        { 'source_team_id' => id, 'source_name' => @game["#{label}Team"], 'internal_team_id' => nil,
          'identity_status' => 'unmapped', 'score' => score(label), 'stats' => BoxNormalizer.new(box&.fetch('raw')).call }
      end

      def score(label)
        score = StatField.new(@game, ["#{label}Points"]).call
        return score unless %w[scheduled postponed cancelled canceled].include?(@game['status']) && score['value']&.zero?

        score.merge('value' => nil, 'availability' => 'unknown', 'reason' => 'nonfinal_placeholder')
      end

      def canonical_status
        contradictory_status? ? 'unknown' : STATUSES.fetch(@game['status'], 'unknown')
      end

      def contradictory_status?
        @boxes.any? { |box| box['raw'].key?('status') && box.dig('raw', 'status') != @game['status'] }
      end

      def source_completed?
        return false if contradictory_status?

        scores = @sides.map { |team| team.dig('score', 'value') }
        @game['status'] == 'final' && scores.none?(NilClass) && scores.uniq.size == 2
      end
    end
  end
end
