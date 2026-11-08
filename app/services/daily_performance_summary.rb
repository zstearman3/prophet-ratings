# frozen_string_literal: true

# Counts each selected game/model and market once, regardless of table sorting.
class DailyPerformanceSummary
  def initialize(rows)
    @rows = rows.uniq(&:identity)
    @statuses = @rows.map { |row| row.straight_up.status }.tally
  end

  def schedule
    { wins:, losses:, graded:, pending: @statuses.fetch('pending', 0), excluded: @statuses.fetch('excluded', 0),
      accuracy: graded.positive? ? wins.to_f / graded : nil }
  end

  def betting
    grouped = BetRecommendationIssue::MARKETS.index_with { |market| market_totals(market) }.transform_keys(&:capitalize)
    grouped.merge('All bets' => DailyBettingTotals.new(@rows.flat_map { |row| row.markets.values }).to_h)
  end

  private

  def wins = @statuses.fetch('correct', 0)
  def losses = @statuses.fetch('incorrect', 0)
  def graded = wins + losses

  def market_totals(market)
    DailyBettingTotals.new(@rows.map { |row| row.markets.fetch(market) }).to_h
  end
end
