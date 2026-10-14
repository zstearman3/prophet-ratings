# frozen_string_literal: true

module ProphetRatings
  # Pure r3 departure component. Publication and combined allocation belong to task 07.
  class DepartureContribution
    def initialize(inputs, config)
      @inputs = ModelConfiguration.freeze_settings(inputs.deep_dup.deep_stringify_keys)
      @config = self.class.validated_configuration(config)
      @settings = @config.fetch(:preseason).fetch(:departures)
      validate_legacy_overlap
      @coverage = nil
    end

    def call
      @coverage = DepartureContributionEvidence.new(@inputs.fetch('reviewed_departures'), @inputs.fetch('team_id'),
                                                    @inputs.fetch('target_year')).call
      report
    end

    private

    public_class_method def self.validated_configuration(config)
      captured = config.deep_dup.deep_symbolize_keys
      ModelConfiguration.validate_contract(captured, captured.fetch(:bundle_name))
      ModelConfiguration.freeze_settings(captured)
    end

    def validate_legacy_overlap
      enabled = @settings.fetch(:weight).positive? || @config.dig(:preseason, :recruiting, :weight).to_f.positive?
      components = legacy_components
      raise ArgumentError, 'Nonzero legacy components overlap reviewed factors' if enabled && components.any? { |value| !value.zero? }
    end

    def profile_values
      values = @inputs.fetch('profile_values').values_at('recruiting_score', 'returning_minutes_pct', 'manual_adjustment')
      unless values.compact.all? { |value| value.is_a?(Numeric) && value.finite? }
        raise ArgumentError, 'Legacy profile values must be finite numeric values'
      end

      values
    end

    def legacy_components
      settings = @config.fetch(:preseason).fetch(:profile)
      recruiting, returning, manual = profile_values
      [(recruiting || 0) * settings.fetch(:recruiting_score_multiplier),
       returning ? (1 - returning) * settings.fetch(:attrition_multiplier) : 0, manual || 0]
    end

    def previous_core_complete?
      values = @inputs.fetch('previous_values').values_at('adj_offensive_efficiency', 'adj_defensive_efficiency')
      unless values.compact.all? { |value| value.is_a?(Numeric) && value.finite? }
        raise ArgumentError, 'Previous core efficiencies must be finite numeric values'
      end

      values.all?(&:present?)
    end

    def raw_contribution
      share = @coverage.fetch('loss_share')
      share ? -(@settings.fetch(:slope) * share) : 0.0
    end

    def capped_contribution
      [raw_contribution, -@settings.fetch(:max_net_efficiency)].max
    end

    def report
      weight = @settings.fetch(:weight)
      { loss_share: @coverage.fetch('loss_share'), coverage: @coverage, previous_core_complete: previous_core_complete?,
        reason:, raw_contribution:, capped_contribution:, weight:,
        contribution: previous_core_complete? && !weight.zero? ? capped_contribution * weight : 0.0,
        formula: @settings.fetch(:formula), bundle_name: @config.fetch(:bundle_name),
        units: 'net_points_per_100_possessions', inputs: @inputs, configuration: @config }
    end

    def reason
      return 'no_complete_previous_core' unless previous_core_complete?
      return @coverage.fetch('reason') unless @coverage.fetch('loss_share')&.positive?
      return 'disabled' if @settings.fetch(:weight).zero?

      'eligible'
    end
  end
end
