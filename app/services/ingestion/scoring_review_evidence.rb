# frozen_string_literal: true

module Ingestion
  # Revalidates supplied counts and metadata; only the enumerated points relationships can be reviewed.
  class ScoringReviewEvidence
    SCORING_REASONS = ['points: component mismatch', 'points disagree with score'].freeze
    attr_reader :payload

    def initialize(observation, season)
      @row = observation.is_a?(::GameObservation) ? observation.raw_payload : observation
      @season = season
      @payload = Cbbd::ImportObservation.new(@row, season).payload
    rescue KeyError, TypeError, NoMethodError
      raise ArgumentError, 'Scoring review requires complete retained CBBD evidence.'
    end

    def self.reviewable?(observation, season)
      new(observation, season).validate
      true
    rescue ArgumentError
      false
    end

    def candidates
      GameObservation::SIDES.to_h { |label| [label.to_s, self.class.totals(payload.fetch(label))] }
    end

    def validate
      validate_scope
      validate_completion
      validate_boxes
      validate_discrepancy
      self
    end

    def selected_payload(choices)
      result = payload.deep_dup
      validate_choices(choices).each { |label, value| apply_total(result, label, value) }
      confirmed_payload(result)
    end

    def self.totals(side)
      [side[:score], side.dig(:stats, :points), shooting_total(side)].compact.uniq
    end

    def self.shooting_total(side)
      values = side.fetch(:stats).values_at(:two_pt_made, :three_pt_made, :free_throws_made)
      values.zip([2, 3, 1]).sum { |value, weight| value * weight } if values.all?(Integer)
    end

    def self.with_total(side, total)
      side.merge(score: total, stats: side.fetch(:stats).merge(points: total))
    end

    private

    def validate_discrepancy
      reject unless candidates.values.any? { |values| values.uniq.size > 1 }
    end

    def validate_scope
      scope = @row.values_at('provider', 'format', 'semantic_profile', 'normalization_version', 'season')
      expected = ['cbbd', CanonicalObservation::FORMAT, CanonicalObservation::SEMANTIC_PROFILE,
                  CanonicalObservation::NORMALIZATION_VERSION, @season.year]
      reject unless scope == expected && @row['conflicts'].to_a.empty?
      reject unless (@row['reasons'].to_a - SCORING_REASONS).empty?
    end

    def validate_completion
      reject unless @row['status'] == 'final' && @row['source_completed'] == true

      GameObservation.new(payload).validate.validate_duration
    rescue GameObservation::Invalid => error
      raise ArgumentError, "Scoring review blocked: #{error.message}"
    end

    def confirmed_payload(result)
      scores = GameObservation::SIDES.map { |label| result.fetch(label).fetch(:score) }
      raise ArgumentError, 'Final scores must differ.' if scores.uniq.size != 2

      GameObservation.new(result).validate.data
    end

    def validate_choices(choices)
      selected = choices.to_h.stringify_keys
      affected = candidates.select { |_label, values| values.uniq.size > 1 }.keys
      raise ArgumentError, 'Select a supplied total for every affected side.' unless selected.keys.sort == affected.sort

      selected
    end

    def apply_total(result, label, value)
      key = label.to_sym
      result[key] = self.class.with_total(result.fetch(key), selected_total(label, value))
    end

    def selected_total(label, value)
      total = Integer(value.to_s, 10, exception: false)
      return total if candidates.fetch(label).include?(total)

      raise ArgumentError, 'Select a supplied total.'
    end

    def validate_boxes
      %w[home away].each { |label| validate_box(@row.fetch(label)) }
    end

    def validate_box(side)
      reject unless side.fetch('stats').values.all? { |field| field['value'].is_a?(Integer) }
      reject unless (Cbbd::BoxValidator.new(side).call - SCORING_REASONS).empty?
    end

    def reject
      raise ArgumentError, 'Only complete final CBBD boxes with scoring-total discrepancies can be reviewed.'
    end
  end
end
