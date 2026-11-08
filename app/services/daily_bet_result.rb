# frozen_string_literal: true

# A simulated one-unit result. Only settled wins, losses and pushes risk a unit.
class DailyBetResult
  attr_reader :recommendation

  def initialize(game, recommendation, exclusion)
    @game = game
    @recommendation = recommendation
    @exclusion = exclusion
  end

  def status
    @status ||= selection_status || game_status || settlement_status
  end

  def reason
    @exclusion || {
      'unavailable' => 'No recommendation saved for this market',
      'excluded' => 'Invalid saved selection, probability, line or price',
      'no_play' => 'Below recommendation threshold', 'void' => 'Canceled game'
    }[status]
  end

  def stake = %w[win loss push].include?(status) ? 1 : 0

  def net_units
    { 'win' => recommendation&.win_profit, 'loss' => -1.0, 'push' => 0.0 }[status]
  end

  def realized_roi = (net_units if stake.positive?)

  private

  def selection_status
    return 'excluded' if @exclusion
    return 'unavailable' unless recommendation
    return 'excluded' unless recommendation.valid_for_settlement?
    return 'no_play' unless recommendation.recommended?

    nil
  end

  def game_status
    return 'void' if @game.canceled?
    return 'pending' unless @game.final?

    nil
  end

  def settlement_status
    margin = recommendation.settlement_margin(home: @game.home_team_score, away: @game.away_team_score)
    return 'push' if margin.zero?

    margin.positive? ? 'win' : 'loss'
  end
end
