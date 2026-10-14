# frozen_string_literal: true

module ProphetRatings
  # Optional experimental r3 curve; old published bundles require no new keys.
  class DepartureContributionSettings
    def self.validate(settings)
      unless settings.is_a?(Hash) && settings[:formula] == 'points_share_v1'
        raise ArgumentError, 'Unsupported departure contribution formula'
      end

      %i[weight slope max_net_efficiency].each do |key|
        value = settings[key]
        raise ArgumentError, "Invalid departure setting: #{key}" unless value.is_a?(Numeric) && value.finite? && value >= 0
      end
      raise ArgumentError, 'Departure weight must be in 0..1' unless (0..1).cover?(settings.fetch(:weight))
    end
  end
end
