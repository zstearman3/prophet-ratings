# frozen_string_literal: true

module ProphetRatings
  # Pure experimental r3 recruiting component; no publication, departure or team cap.
  class RecruitingContribution
    def initialize(inputs, config)
      @inputs = ModelConfiguration.freeze_settings(inputs.deep_dup.deep_stringify_keys)
      @config = config.deep_dup.deep_symbolize_keys
      validate_configuration
      @settings = @config.fetch(:preseason).fetch(:recruiting)
      @weight = @settings.fetch(:weight)
    end

    def call
      baseline = PreseasonPriorFormula.new(@inputs, @config).unadjusted_efficiencies
      points = class_points
      component_report(points, self.class.baseline_net(baseline)).merge(
        baseline:, formula: @settings.fetch(:formula), bundle_name: @config.fetch(:bundle_name),
        units: 'net_points_per_100_possessions', inputs: @inputs, configuration: @config
      )
    end

    def self.baseline_net(baseline)
      net = baseline.fetch('adj_offensive_efficiency').fetch(:value) - baseline.fetch('adj_defensive_efficiency').fetch(:value)
      raise ArgumentError, 'Unadjusted baseline net efficiency must be finite' unless net.finite?

      net
    end

    def self.reviewed_points(evidence)
      case evidence.values_at('status', 'class_points')
      in ['unknown', nil] then nil
      in [status, points] then validated_points(points, status)
      end
    end

    def self.validated_points(points, status)
      number = Float(points, exception: false)
      unless number&.finite? && number >= 0 && valid_status?(status, number)
        raise ArgumentError, 'Invalid reviewed recruiting points/status'
      end

      number
    end

    def self.valid_status?(status, points)
      { 'verified_zero' => points.zero?, 'verified_points' => points.positive? }.fetch(status, false)
    end

    private

    def validate_configuration
      ModelConfiguration.validate_contract(@config, @config.fetch(:bundle_name))
      ModelConfiguration.freeze_settings(@config)
    end

    def component_report(points, net)
      quality = points ? fraction(points, :class_points) : 0.0
      attenuation = 1 - ((1 - @settings.fetch(:attenuation_floor)) * fraction(net, :baseline_net))
      raw = @settings.fetch(:max_net_efficiency) * quality * attenuation
      { baseline_net: net, class_points: points, reason: reason(points),
        eligible: points.present? && points > @settings.fetch(:class_points_lower), class_fraction: quality, attenuation:,
        raw_contribution: raw, weight: @weight, contribution: raw * @weight }
    end

    def class_points
      evidence = @inputs.fetch('reviewed_recruiting')
      case evidence
      when NilClass then nil
      when Hash
        validate_units(evidence)
        self.class.reviewed_points(evidence)
      else raise ArgumentError, 'Invalid reviewed recruiting evidence'
      end
    end

    def validate_units(evidence)
      return if %w[247_recruit_composite_class_points cbbd_recruit_composite_class_points].include?(evidence.dig('units', 'class_points'))

      raise ArgumentError, 'Recruiting requires Recruit Composite class points units'
    end

    def fraction(value, band)
      lower = @settings.fetch(:"#{band}_lower")
      upper = @settings.fetch(:"#{band}_upper")
      (value.clamp(lower, upper) - lower).to_f / (upper - lower)
    end

    def reason(points)
      return 'missing_class_points' if points.blank?
      return 'below_threshold' if points <= @settings.fetch(:class_points_lower)
      return 'disabled' if @weight.zero?

      'eligible'
    end
  end
end
