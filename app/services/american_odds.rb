# frozen_string_literal: true

# Shared boundary for usable American prices; no text coercion or substitute prices.
module AmericanOdds
  def self.valid?(price)
    price.is_a?(Numeric) && price.real? && price.finite? && price.abs >= 100
  end

  def self.net_win(price)
    return unless valid?(price)

    price.positive? ? price / 100.0 : 100.0 / price.abs
  end

  def self.consensus(prices)
    probabilities = prices.filter_map { |price| implied_probability(price) if valid?(price) }
    return if probabilities.empty?

    from_probability(probabilities.sum / probabilities.size)
  end

  def self.implied_probability(price)
    magnitude = price.to_r.abs
    denominator = magnitude + 100
    price.positive? ? 100 / denominator : magnitude / denominator
  end

  def self.from_probability(probability)
    # Exact ratios preserve canonical even money and round only the final price.
    complement = 1 - probability
    odds = if probability <= Rational(1, 2)
             100 * complement / probability
           else
             -100 * probability / complement
           end
    odds.round
  end

  private_class_method :implied_probability, :from_probability
end
