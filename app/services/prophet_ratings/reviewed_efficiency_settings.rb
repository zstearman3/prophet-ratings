# frozen_string_literal: true

module ProphetRatings
  # Opt-in integration; component-only preview configurations retain legacy dispatch.
  class ReviewedEfficiencySettings
    def self.validate(preseason)
      return unless preseason.key?(:efficiency_adjustment)

      settings = preseason.fetch(:efficiency_adjustment)
      raise ArgumentError, 'Unsupported reviewed efficiency formula' unless settings.is_a?(Hash) && settings[:formula] == 'reviewed_net_v1'

      validate_components(preseason)
      validate_bounds(settings)
    end

    def self.validate_components(preseason)
      %i[recruiting departures].each { |key| preseason.fetch(key) }
    end

    def self.validate_bounds(settings)
      lower, upper = settings.values_at(:lower_bound, :upper_bound)
      return if [lower, upper].all? { |value| value.is_a?(Numeric) && value.finite? } && lower <= 0 && upper >= 0

      raise ArgumentError, 'Combined efficiency bounds must be finite and lower <= 0 <= upper'
    end
  end
end
