# frozen_string_literal: true

module ProphetRatings
  # Pure replay of the captured v1 preseason contract; no database or runtime defaults.
  class PreseasonPriorFormula
    STATS = %w[adj_offensive_efficiency adj_defensive_efficiency adj_pace].freeze

    def initialize(inputs, config)
      @inputs = inputs.deep_stringify_keys
      @config = config.deep_stringify_keys.fetch('preseason')
      @profile = @inputs.fetch('profile_values')
      @profile_config = @config.fetch('profile')
    end

    def call
      {
        preseason_adj_offensive_efficiency: blended_stat('adj_offensive_efficiency') + profile_adjustment,
        preseason_adj_defensive_efficiency: blended_stat('adj_defensive_efficiency') - profile_adjustment,
        preseason_adj_pace: blended_stat('adj_pace')
      }.stringify_keys.transform_values { |value| value.round(3) }
    end

    private

    def blended_stat(stat)
      baseline = @inputs.fetch('baselines').fetch(stat).to_f
      previous = @inputs.fetch('previous_values').fetch(stat)
      return baseline unless previous

      weight = @config.fetch('previous_season_weight')
      ((1 - weight) * baseline) + (weight * previous.to_f)
    end

    def profile_adjustment
      limit = @profile_config.fetch('max_efficiency_adjustment')
      (recruitment - attrition + @profile.fetch('manual_adjustment', nil).to_f).clamp(-limit, limit)
    end

    def recruitment
      @profile.fetch('recruiting_score', nil).to_f * @profile_config.fetch('recruiting_score_multiplier')
    end

    def attrition
      returning = @profile.fetch('returning_minutes_pct', nil)
      returning ? @profile_config.fetch('attrition_multiplier') * (1 - returning.to_f) : 0.0
    end
  end
end
