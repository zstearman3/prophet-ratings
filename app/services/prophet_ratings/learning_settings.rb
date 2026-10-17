# frozen_string_literal: true

module ProphetRatings
  # Missing blocks preserve the historical learning rule for published models.
  class LearningSettings
    LEGACY = {
      volatility: { minimum_observations: 4, sample_scale: 16.0, maximum_weight: 0.5 },
      home_court: { minimum_observations: 1, sample_scale: 16.0, maximum_weight: 0.5 }
    }.freeze

    def self.for(config, kind)
      config.fetch(:learning, LEGACY).fetch(kind)
    end

    def self.validate(config)
      return unless config.key?(:learning)

      rules = config[:learning]
      unless rules.is_a?(Hash) && rules.keys.sort == LEGACY.keys.sort
        raise ArgumentError, 'learning must contain volatility and home_court rules'
      end

      rules.each { |kind, rule| validate_rule(rule, kind) }
    end

    def self.validate_rule(rule, kind)
      raise ArgumentError, "Invalid learning.#{kind} settings" unless rule.is_a?(Hash) && rule.keys.sort == LEGACY.fetch(kind).keys.sort

      validate_minimum(rule, kind)
      validate_curve(rule, kind)
    end

    def self.validate_minimum(rule, kind)
      minimum = rule.fetch(:minimum_observations)
      floor = kind == :volatility ? 2 : 1
      return if minimum.is_a?(Integer) && minimum >= floor

      raise ArgumentError, "learning.#{kind}.minimum_observations must be an integer >= #{floor}"
    end

    def self.validate_curve(rule, kind)
      scale, cap = rule.values_at(:sample_scale, :maximum_weight)
      unless scale.is_a?(Numeric) && scale.finite? && scale.positive?
        raise ArgumentError, "learning.#{kind}.sample_scale must be finite and positive"
      end
      return if cap.is_a?(Numeric) && cap.finite? && (0..1).cover?(cap)

      raise ArgumentError, "learning.#{kind}.maximum_weight must be in 0..1"
    end

    def self.weight(count, rule)
      return 0.0 if count < rule.fetch(:minimum_observations)

      [count / rule.fetch(:sample_scale).to_f, rule.fetch(:maximum_weight)].min.round(4)
    end
  end
end
