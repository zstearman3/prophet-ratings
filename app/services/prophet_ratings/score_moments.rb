# frozen_string_literal: true

module ProphetRatings
  # Exact second moments of P*H/100 and P*A/100 for independent normal H, A, P.
  class ScoreMoments
    def initialize(means:, deviations:)
      validate_means(means)
      ModelConfiguration.validate_volatilities(deviations.values_at(:home, :away, :pace))
      @means = means
      @variances = deviations.transform_values { |value| value**2 }
    end

    def home_variance
      product_variance(@means.fetch(:home), @variances.fetch(:home))
    end

    def away_variance
      product_variance(@means.fetch(:away), @variances.fetch(:away))
    end

    def score_covariance
      @variances.fetch(:pace) * @means.fetch(:home) * @means.fetch(:away) / 10_000.0
    end

    def margin_variance
      product_variance(efficiency_difference, efficiency_variance)
    end

    def total_variance
      product_variance(@means.fetch(:home) + @means.fetch(:away), efficiency_variance)
    end

    # Physical positive pace preserves the sign of H-A. The raw normal pace tail
    # can be nonpositive; simulation agreement is approximate to that tail.
    def home_win_probability
      return deterministic_probability if efficiency_variance.zero?

      StatisticsUtils.normal_cdf(efficiency_difference / Math.sqrt(efficiency_variance))
    end

    private

    def validate_means(means)
      values = means.values_at(:home, :away, :pace)
      raise ArgumentError, 'Prediction means must be finite numbers' unless values.all? { |value| value.is_a?(Numeric) && value.finite? }
      raise ArgumentError, 'Expected pace must be positive' unless means.fetch(:pace).positive?
    end

    def deterministic_probability
      case efficiency_difference <=> 0
      when 1 then 1.0
      when -1 then 0.0
      else 0.5
      end
    end

    def efficiency_difference
      @means.fetch(:home) - @means.fetch(:away)
    end

    def efficiency_variance
      @variances.fetch(:home) + @variances.fetch(:away)
    end

    def product_variance(mean, variance)
      pace_variance = @variances.fetch(:pace)
      ((((@means.fetch(:pace)**2) + pace_variance) * variance) + (pace_variance * (mean**2))) / 10_000.0
    end
  end
end
