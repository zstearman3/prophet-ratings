# frozen_string_literal: true

# The existing recommendation display interface over immutable JSON, never live odds.
class SavedBetRecommendation
  include BettingSelection

  attr_reader :game, :prediction, :bet_type

  def initialize(saved, game:, prediction:, bet_type:)
    @saved = saved
    @game = game
    @prediction = prediction
    @bet_type = bet_type
  end

  def team = @saved['team']
  def vegas_line = @saved['vegas_line']
  def vegas_odds = @saved['vegas_odds']
  def model_value = @saved['model_value']
  def confidence = @saved['confidence']
  def ev = @saved['ev']

  def recommended? = @saved['recommended']
  def spread_bet_type? = bet_type == 'spread'
  def moneyline_bet_type? = bet_type == 'moneyline'
  def total_bet_type? = bet_type == 'total'
  def valid_odds? = AmericanOdds.valid?(vegas_odds)
  def recommendation = recommended? && valid_odds? ? evaluated_selection : 'No play'

  def evaluated_selection
    return unless valid_odds?

    return team_selection if %w[home away].include?(team)
    return unless %w[over under].include?(team) && vegas_line

    "#{team.capitalize} #{format('%g', vegas_line)}"
  end

  private

  def team_selection
    value = spread_bet_type? ? vegas_line : vegas_odds
    name = @saved.dig('team_names', team)
    format('%<name>s %<value>+g', name:, value:) if value
  end
end
