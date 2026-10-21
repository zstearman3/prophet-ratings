# frozen_string_literal: true

module Ingestion
  module Reconciliation
    # Keeps normalized missingness and independently demonstrated inconsistency evidence.
    class ShadowSide
      DEFECT_REASONS = ['component mismatch', 'made exceeds attempts', 'invalid regulation/overtime duration'].freeze
      COMPONENTS = { 'rebounds' => %w[offensive_rebounds defensive_rebounds],
                     'field_goals_made' => %w[two_pt_made three_pt_made],
                     'field_goals_attempted' => %w[two_pt_attempted three_pt_attempted] }.freeze

      def initialize(game:, source:, alignment:)
        @game = game
        @source = source
        @side, @local_side = alignment
      end

      def call
        [stat_difference('score', @source.fetch('score'), @game.public_send("#{@local_side}_team_score"))] +
          @source.fetch('stats').map { |name, stat| stat_difference(name, stat) }
      end

      def self.inconsistent?(name, local)
        return false unless local && COMPONENTS.key?(name)

        values = COMPONENTS.fetch(name).map { |field| local.public_send(field) }
        total = local.public_send(name)
        values.none?(nil) && total.present? && values.sum != total
      end

      private

      def local
        @game.public_send("#{@local_side}_team_game")
      end

      def stat_difference(name, stat, local_value = local&.public_send(name))
        difference(name, [stat['value'], local_value]).merge(
          'category' => category(name, stat, local_value),
          'evidence' => { 'source_stat' => stat, 'local_team_game_id' => local&.id, 'local_semantic_profile' => 'uncertified',
                          'local_components' => local_components(name), 'source_validation_reasons' => validation_reasons(name) }
        )
      end

      def local_components(name)
        COMPONENTS.fetch(name, []).index_with { |field| local&.public_send(field) }
      end

      def validation_reasons(name)
        Cbbd::BoxValidator.new(@source).call & DEFECT_REASONS.map { |reason| "#{name}: #{reason}" }
      end

      def category(name, stat, local_value)
        return 'likely_provider_defect' if stat['reason'] == 'invalid_nonnegative_integer' || validation_reasons(name).any?
        return 'likely_local_defect' if ShadowSide.inconsistent?(name, local)
        return 'unresolved_evidence' if [stat['value'], local_value].any?(nil)
        return 'semantics' if %w[rebounds offensive_rebounds defensive_rebounds turnovers].include?(name)

        'unresolved_evidence'
      end

      def difference(name, values)
        Shadow.difference('local_game_id' => @game.id, 'field' => "#{@side}.#{name}", 'source' => values.first, 'local' => values.last)
      end
    end
  end
end
