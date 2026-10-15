# frozen_string_literal: true

module ProphetRatings
  # One net cap and symmetric allocation, using only frozen operands and model settings.
  class ReviewedEfficiencyAdjustment
    def initialize(inputs, config)
      @inputs = inputs.deep_stringify_keys
      @config = DepartureContribution.validated_configuration(config)
      @settings = @config.fetch(:preseason).fetch(:efficiency_adjustment)
      validate_captured_configuration
    end

    def call
      recruiting = RecruitingContribution.new(@inputs, @config).call.except(:inputs, :configuration)
      departures = DepartureContribution.new(@inputs, @config).call.except(:inputs, :configuration)
      combined_report(recruiting, departures)
    end

    private

    def validate_captured_configuration
      captured = @inputs['configuration']
      return unless captured && captured != @config.deep_stringify_keys

      raise ArgumentError, 'Reviewed preseason replay requires the captured immutable configuration'
    end

    def combined_report(recruiting, departures)
      sum = recruiting.fetch(:contribution) + departures.fetch(:contribution)
      lower, upper = @settings.values_at(:lower_bound, :upper_bound)
      raise ArgumentError, 'Combined efficiency contribution must be finite' unless sum.finite?

      adjustment = sum.clamp(lower, upper)
      { formula: @settings.fetch(:formula), units: 'net_points_per_100_possessions',
        enabled: recruiting.fetch(:weight).positive? || departures.fetch(:weight).positive?,
        recruiting:, departures:, pre_cap_sum: sum, lower_bound: lower, upper_bound: upper, adjustment:,
        offense_allocation: adjustment / 2.0, defense_allocation: -adjustment / 2.0 }
    end
  end
end
