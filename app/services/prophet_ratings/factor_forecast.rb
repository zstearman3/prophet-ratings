# frozen_string_literal: true

module ProphetRatings
  # Optional, versioned diagnostics. These forecasts do not affect score predictions.
  class FactorForecast
    FIELDS = {
      effective_fg_percentage: %w[adj_effective_fg_percentage adj_effective_fg_percentage_allowed],
      turnover_rate: %w[adj_turnover_rate adj_turnover_rate_forced],
      offensive_rebound_rate: %w[adj_offensive_rebound_rate adj_defensive_rebound_rate],
      free_throw_rate: %w[adj_free_throw_rate adj_free_throw_rate_allowed],
      three_pt_proficiency: %w[adj_three_pt_proficiency adj_three_pt_proficiency_allowed]
    }.freeze
    SETTINGS = %i[ridge_alpha anchor_weight offense_weight defense_weight].freeze

    def self.validate(config)
      factors = config[:factors]
      return unless factors

      validate_contract(factors, config)
      factors.each_value { |settings| validate_weights(settings) }
    end

    def self.validate_contract(factors, config)
      unless factors.is_a?(Hash) && factors.keys.sort == FIELDS.keys.sort
        raise ArgumentError, 'Factor settings must specify exactly the five factors'
      end
      raise ArgumentError, 'Factor forecasts require corrected_v1' unless config[:ratings_formula] == 'corrected_v1'
    end

    def self.validate_weights(settings)
      unless settings.is_a?(Hash) && settings.keys.sort == SETTINGS.sort &&
             settings.values.all? { |value| value.is_a?(Numeric) && value.finite? && value >= 0 }
        raise ArgumentError, 'Factor weights must be finite nonnegative numbers with all four settings present'
      end
      return if settings.values_at(:offense_weight, :defense_weight).all? { |value| value <= 1 }

      raise ArgumentError, 'Factor forecast weights must be in 0..1'
    end

    def self.anchors(season)
      FIELDS.keys.index_with { |name| season.rating_team_seasons.average(name)&.to_f }
    end

    def self.capture(snapshots, config)
      return {} unless config[:factors]

      FIELDS.to_h do |name, fields|
        inputs = capture_inputs(snapshots, name, fields)
        [name.to_s, forecasts(inputs, config.fetch(:factors).fetch(name))]
      end.compact
    end

    def self.capture_inputs(snapshots, name, fields)
      snapshots.map { |snapshot| factor_inputs(snapshot, name, fields) }
    end

    def self.factor_inputs(snapshot, name, fields)
      offense, defense = fields.map { |field| snapshot.public_send(field) }
      defense = 1.0 - defense if name == :offensive_rebound_rate && defense
      { offense:, defense:, baseline: snapshot.stats.dig('factor_anchors', name.to_s) }
    end

    def self.forecasts(inputs, weights)
      return unless inputs.flat_map(&:values).all? { |value| value.is_a?(Numeric) && value.finite? }

      baseline = inputs.sum { |input| input.fetch(:baseline) } / 2.0
      { 'inputs' => inputs, 'baseline' => baseline,
        'home' => baseline + adjustment(inputs, weights), 'away' => baseline + adjustment(inputs.reverse, weights) }
    end

    def self.adjustment(inputs, weights)
      offense, defense = inputs
      (weights.fetch(:offense_weight) * (offense.fetch(:offense) - offense.fetch(:baseline))) +
        (weights.fetch(:defense_weight) * (defense.fetch(:defense) - defense.fetch(:baseline)))
    end
  end
end
