# frozen_string_literal: true

# Ratios use total settled stakes, including pushes, and unrounded unit profits.
class DailyBettingTotals
  def initialize(results)
    @results = results
    @statuses = results.map(&:status).tally
  end

  def to_h
    { wins: @statuses.fetch('win', 0), losses: @statuses.fetch('loss', 0), pushes: @statuses.fetch('push', 0),
      settled: stakes, stakes:, net_units:, roi: }
  end

  def stakes = @results.sum(&:stake)
  def net_units = @results.sum { |result| result.net_units || 0 }

  def roi
    risked = stakes
    net_units / risked if risked.positive?
  end
end
