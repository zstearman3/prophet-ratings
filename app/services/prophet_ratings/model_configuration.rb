# frozen_string_literal: true

module ProphetRatings
  # A complete stored payload. Legacy ratings-only rows remain readable, but cannot be replayed.
  class ModelConfiguration
    NUMERIC_SETTINGS = %w[
      preseason.previous_season_weight preseason.fallback_efficiency preseason.fallback_pace
      preseason.adjustment_start_after_days preseason.profile.recruiting_score_multiplier
      preseason.profile.attrition_multiplier preseason.profile.max_efficiency_adjustment
      weighting.recency_decay_days weighting.min_recency_weight weighting.preseason_decay_days
      weighting.min_preseason_weight blowout.max_margin blowout.cap_multiplier
      baseline_volatility.efficiency_volatility baseline_volatility.pace_volatility
      home_court_advantage ridge.alpha anchor.weight prediction.confidence_levels.high_max
      prediction.confidence_levels.medium_max defaults.season_defaults.average_pace
      defaults.season_defaults.average_efficiency
    ].freeze

    def self.settings(version)
      payload = version.config.deep_symbolize_keys
      validate_contract(payload, version.name)
      freeze_settings(payload)
    end

    def self.validate_contract(payload, name)
      unless payload[:contract_version] == 1
        raise ArgumentError, "Model #{name} lacks the complete configuration contract; publish a new version"
      end

      NUMERIC_SETTINGS.each { |path| validate_number(payload, path) }
      raise ArgumentError, 'Missing home_court_adjusted_stats' unless payload[:home_court_adjusted_stats].is_a?(Array)

      validate_bounds(payload)
    end

    def self.validate_number(payload, path)
      value = payload.dig(*path.split('.').map(&:to_sym))
      return if value.is_a?(Numeric) && value.finite? && value >= 0

      raise ArgumentError, "Invalid or missing model setting: #{path}"
    end

    def self.validate_bounds(payload)
      %w[weighting.recency_decay_days weighting.preseason_decay_days blowout.max_margin
         preseason.fallback_efficiency preseason.fallback_pace defaults.season_defaults.average_pace
         defaults.season_defaults.average_efficiency baseline_volatility.efficiency_volatility
         baseline_volatility.pace_volatility].each do |path|
        raise ArgumentError, "Model setting must be positive: #{path}" unless payload.dig(*path.split('.').map(&:to_sym)).positive?
      end
      validate_weights(payload)
    end

    def self.validate_weights(payload)
      %w[preseason.previous_season_weight weighting.min_recency_weight weighting.min_preseason_weight].each do |path|
        raise ArgumentError, "Model weight must be in 0..1: #{path}" unless (0..1).cover?(payload.dig(*path.split('.').map(&:to_sym)))
      end
    end

    def self.freeze_settings(value)
      nested_values(value).each { |child| freeze_settings(child) }
      value.freeze
    end

    def self.nested_values(value)
      case value
      when Hash then value.values
      when Array then value
      else []
      end
    end

    def self.for_snapshots(home, away, version = nil)
      raise ArgumentError, 'Missing home or away rating snapshot' unless home && away

      version ||= home.ratings_config_version
      validate_snapshots([home, away], version)
      validated_version(version)
    end

    def self.validated_version(version)
      version.settings
      version
    end

    def self.validate_snapshots(snapshots, version)
      return if version && snapshots.all? { |snapshot| snapshot && snapshot.ratings_config_version_id == version.id }

      raise ArgumentError, 'Rating snapshots must use the selected model version'
    end

    def self.snapshot_volatilities(snapshots, version)
      validate_snapshots(snapshots, version)
      values = snapshots.flat_map do |snapshot|
        [snapshot.offensive_efficiency_volatility, snapshot.defensive_efficiency_volatility]
      end
      validate_volatilities(values)
      values
    end

    def self.validate_volatilities(values)
      return if values.all? { |value| value&.finite? && value >= 0 }

      raise ArgumentError, 'Stored prediction uncertainty requires valid snapshot volatility'
    end
  end
end
