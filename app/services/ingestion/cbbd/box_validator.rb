# frozen_string_literal: true

module Ingestion
  module Cbbd
    # Applies the existing score identities and possession coefficient to known totals.
    class BoxValidator
      COMPONENTS = {
        'points' => { 'two_pt_made' => 2, 'three_pt_made' => 3, 'free_throws_made' => 1 },
        'field_goals_made' => { 'two_pt_made' => 1, 'three_pt_made' => 1 },
        'field_goals_attempted' => { 'two_pt_attempted' => 1, 'three_pt_attempted' => 1 },
        'rebounds' => { 'offensive_rebounds' => 1, 'defensive_rebounds' => 1 }
      }.freeze

      def initialize(side)
        @side = side
        @values = side.fetch('stats').transform_values { |field| field['value'] }
      end

      def call
        return missing_reasons if @values.values.any?(NilClass)

        relationship_reasons + duration_reasons
      end

      private

      def missing_reasons
        @values.select { |_name, value| value.is_a?(NilClass) }.keys.map { |field| "#{field}: #{@side['stats'][field]['reason']}" }
      end

      def relationship_reasons
        reasons = shot_reasons + component_reasons
        reasons << 'points disagree with score' unless @values['points'] == @side.dig('score', 'value')
        reasons << 'possessions must be positive' unless possessions.positive?
        reasons
      end

      def shot_reasons
        %w[field_goals two_pt three_pt free_throws].filter_map do |category|
          "#{category}: made exceeds attempts" if @values["#{category}_made"] > @values["#{category}_attempted"]
        end
      end

      def component_reasons
        COMPONENTS.filter_map do |field, parts|
          "#{field}: component mismatch" unless @values[field] == component_total(parts)
        end
      end

      def component_total(parts)
        parts.sum { |key, multiplier| @values[key] * multiplier }
      end

      def duration_reasons
        return [] if @values.fetch('minutes').between?(200, StatField::MAX_INTEGER) && ((@values['minutes'] - 200) % 25).zero?

        ['minutes: invalid regulation/overtime duration']
      end

      def possessions
        (@values['field_goals_attempted'] - @values['offensive_rebounds'] + @values['turnovers'] +
          (0.475 * @values['free_throws_attempted'])).round(1)
      end
    end
  end
end
