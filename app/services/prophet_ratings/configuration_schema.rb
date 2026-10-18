# frozen_string_literal: true

module ProphetRatings
  # Authoring guard: reject ignored keys before publication, without invalidating old stored bundles.
  class ConfigurationSchema
    LEARNING = { minimum_observations: nil, sample_scale: nil, maximum_weight: nil }.freeze
    PRESEASON = {
      previous_season_weight: nil, fallback_efficiency: nil, fallback_pace: nil, adjustment_start_after_days: nil,
      profile: { recruiting_score_multiplier: nil, attrition_multiplier: nil, max_efficiency_adjustment: nil },
      coaching: { formula: nil, weight: nil, max_adjustment: nil },
      recruiting: (RecruitingContributionSettings::NUMBERS + [:formula]).index_with(nil),
      departures: { formula: nil, weight: nil, slope: nil, max_net_efficiency: nil },
      efficiency_adjustment: { formula: nil, lower_bound: nil, upper_bound: nil }
    }.freeze
    ROOT = {
      contract_version: nil, bundle_name: nil, ratings_formula: nil, early_season_policy: nil, preseason: PRESEASON,
      weighting: { recency_decay_days: nil, min_recency_weight: nil, preseason_decay_days: nil, min_preseason_weight: nil },
      blowout: { enabled: nil, max_margin: nil, cap_multiplier: nil },
      baseline_volatility: { efficiency_volatility: nil, pace_volatility: nil },
      home_court_advantage: nil, home_court_adjusted_stats: nil,
      ridge: { alpha: nil }, anchor: { weight: nil },
      prediction: { uncertainty_model: nil, confidence_levels: { high_max: nil, medium_max: nil } },
      defaults: { season_defaults: { average_pace: nil, average_efficiency: nil } },
      factors: FactorForecast::FIELDS.keys.index_with { FactorForecast::SETTINGS.index_with(nil) },
      learning: { volatility: LEARNING, home_court: LEARNING }
    }.freeze

    def self.validate(payload)
      levels = payload.fetch(:prediction).fetch(:confidence_levels)
      unless levels.fetch(:high_max) <= levels.fetch(:medium_max)
        raise ArgumentError, 'prediction.confidence_levels.high_max must be <= medium_max'
      end

      validate_home_stats(payload)
    end

    def self.validate_keys(values, schema, path)
      raise ArgumentError, "#{path} must be an object" unless values.is_a?(Hash)

      reject_unknown(values.keys - schema.keys, path)

      values.each do |key, value|
        nested = schema.fetch(key)
        validate_keys(value, nested, "#{path}.#{key}") if nested
      end
    end

    def self.reject_unknown(unknown, path)
      raise ArgumentError, "Unknown model setting: #{path}.#{unknown.first}" if unknown.any?
    end

    def self.validate_home_stats(payload)
      stats = payload.fetch(:home_court_adjusted_stats)
      return if stats.uniq == stats && (stats - %w[offensive_efficiency defensive_efficiency]).empty?

      raise ArgumentError, 'home_court_adjusted_stats must contain unique efficiency stat names (boost is in points per 100 possessions)'
    end
  end
end
