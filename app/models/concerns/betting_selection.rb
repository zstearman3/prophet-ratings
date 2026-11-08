# frozen_string_literal: true

# Shared selection semantics for mutable display rows and immutable saved picks.
module BettingSelection
  def valid_for_settlement?
    sides = total_bet_type? ? %w[over under] : %w[home away]
    valid_odds? && valid_probability? && [true, false].include?(recommended?) && sides.include?(team) &&
      (moneyline_bet_type? || ProphetRatings::EvaluationObservation.finite?(vegas_line))
  end

  def valid_probability?
    value = confidence
    ProphetRatings::EvaluationObservation.finite?(value) && (0..1).cover?(value)
  end

  def settlement_margin(home:, away:)
    return total_settlement_margin(home, away) if total_bet_type?

    margin = team == 'home' ? home - away : away - home
    margin + (spread_bet_type? ? vegas_line : 0)
  end

  def win_profit = AmericanOdds.net_win(vegas_odds)

  private

  def total_settlement_margin(home, away)
    (home + away - vegas_line) * (team == 'over' ? 1 : -1)
  end
end
