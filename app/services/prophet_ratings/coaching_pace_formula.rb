# frozen_string_literal: true

module ProphetRatings
  # Replay uses only frozen operands, never coaching records or season averages.
  class CoachingPaceFormula
    def initialize(inputs, settings)
      @inputs = inputs.deep_stringify_keys
      @settings = settings.deep_stringify_keys
      @weight = @settings.fetch('weight')
      ModelConfiguration.validate_coaching(preseason: { coaching: @settings.deep_symbolize_keys })
    end

    def call(existing)
      report(existing).fetch(:new_pace).tap { |value| self.class.positive_pace(value.round(3)) }
    end

    def report(existing)
      signal = validated_signal(existing)
      adjustment = signal ? (@weight * (signal - existing)).clamp(-cap, cap) : 0
      result = validated_result(existing + adjustment)
      { reason: @inputs.fetch('reason'), old_pace: existing, signal:, weight: @weight, cap:, adjustment:, new_pace: result }
    end

    def self.positive_pace(value)
      return if value.is_a?(Numeric) && value.finite? && value.positive?

      raise ArgumentError, 'Coaching pace requires finite positive numeric operands and output'
    end

    private

    def validated_signal(existing)
      target = @inputs.fetch('target_anchor')
      validator = self.class
      [existing, target].each { |value| validator.positive_pace(value) }
      coach_signal(target) if eligible?
    end

    def eligible?
      status = @inputs.fetch('reason')
      raise ArgumentError, 'Unknown coaching eligibility reason' unless CoachingPaceInputs::REASONS.include?(status)

      status == 'eligible'
    end

    def coach_signal(target)
      pace, baseline = source_paces
      validated_result(target + (pace - baseline))
    end

    def source_paces
      validator = self.class
      @inputs.values_at('source_adjusted_pace', 'source_baseline').tap do |values|
        values.each { |value| validator.positive_pace(value) }
      end
    end

    def validated_result(value)
      self.class.positive_pace(value)
      value
    end

    def cap
      @settings.fetch('max_adjustment')
    end
  end
end
