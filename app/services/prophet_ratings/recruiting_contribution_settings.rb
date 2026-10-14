# frozen_string_literal: true

module ProphetRatings
  # Optional r3 component configuration. Existing published bundles need no new keys.
  class RecruitingContributionSettings
    NUMBERS = %i[weight class_points_lower class_points_upper baseline_net_lower baseline_net_upper
                 attenuation_floor max_net_efficiency].freeze

    def self.validate(settings)
      unless settings.is_a?(Hash) && settings[:formula] == 'class_points_baseline_v1'
        raise ArgumentError, 'Unsupported recruiting contribution formula'
      end

      NUMBERS.each do |key|
        value = settings[key]
        raise ArgumentError, "Invalid recruiting setting: #{key}" unless value.is_a?(Numeric) && value.finite?
      end
      validate_ranges(settings)
    end

    def self.validate_ranges(settings)
      %i[weight attenuation_floor].each do |key|
        raise ArgumentError, "Recruiting #{key} must be in 0..1" unless (0..1).cover?(settings.fetch(key))
      end
      %i[class_points baseline_net].each { |band| validate_band(settings, band) }
      validate_magnitudes(settings)
    end

    def self.validate_magnitudes(settings)
      return if settings.fetch(:max_net_efficiency) >= 0 && settings.fetch(:class_points_lower) >= 0

      raise ArgumentError, 'Recruiting ceiling and class points must be nonnegative'
    end

    def self.validate_band(settings, band)
      lower = settings.fetch(:"#{band}_lower")
      upper = settings.fetch(:"#{band}_upper")
      return if upper > lower && (upper - lower).finite?

      raise ArgumentError, "Recruiting #{band} endpoints must be strictly ordered with a finite span"
    end
  end
end
