# frozen_string_literal: true

module ProphetRatings
  # Opt-in eligibility and numerical safeguards; absent selectors retain historical behavior.
  class EarlySeasonPolicy
    def self.enabled?(config)
      config[:early_season_policy] == 'coherent_v1'
    end

    def self.adjustment_period?(season, as_of, config)
      days = as_of.to_date - season.start_date
      enabled?(config) ? days >= 0 : days > config.dig(:preseason, :adjustment_start_after_days)
    end

    def self.validate(config)
      policy = config[:early_season_policy]
      raise ArgumentError, 'Unsupported early-season policy' unless [nil, 'coherent_v1'].include?(policy)
      return unless policy

      validate_regularization(config)
    end

    def self.validate_regularization(config)
      raise ArgumentError, 'Coherent early-season ratings require corrected_v1' unless config[:ratings_formula] == 'corrected_v1'
      return if positive_ridge?(config)

      raise ArgumentError, 'Coherent early-season ratings require positive ridge for every stat'
    end

    def self.positive_ridge?(config)
      penalties = [config.dig(:ridge, :alpha)] + (config[:factors] || {}).values.pluck(:ridge_alpha)
      penalties.all? { |value| value.is_a?(Numeric) && value.finite? && value.positive? }
    end

    def self.usable_observation?(observed, weight, config)
      return observed.present? unless enabled?(config)

      observed.is_a?(Numeric) && observed.finite? && weight.positive?
    end

    def self.supported_columns(rows, config)
      return [] unless config[:early_season_policy]

      rows[0...-1].transpose.map { |column| column.any?(&:nonzero?) }
    end

    def self.supported_stats(stats, context)
      supported, columns = context.values_at(:supported_columns, :columns)
      stats.select { |field, _value| supported.fetch(columns.fetch(field)) }
    end

    def self.usable_fit?(center, observations, config)
      !enabled?(config) || (center.finite? && observations.any?)
    end
  end
end
