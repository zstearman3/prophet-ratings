# frozen_string_literal: true

# Service to generate BetRecommendation rows for a game with a prediction and game odds
class BetRecommendationGenerator
  BETTING_CONFIG = Rails.application.config_for(:betting).deep_symbolize_keys

  def self.call(game:)
    new(game).call
  end

  def initialize(game)
    @game = game
  end

  # Generates bet recommendations for a given game
  # @param game [Game] the game to generate recommendations for
  # @return [Array<BetRecommendation>] created recommendations
  def call
    prediction = game.current_prediction
    game_odd = game.game_odd
    recs = []

    recs << generate_spread_recommendation(prediction, game_odd)
    recs << generate_moneyline_recommendation(prediction, game_odd)
    recs << generate_total_recommendation(prediction, game_odd)

    recs
  end

  private

  attr_reader :game

  def generate_spread_recommendation(prediction, game_odd)
    return unless game_odd.spread_point

    model_margin = prediction.home_score - prediction.away_score
    stddev = prediction.margin_std_deviation
    line = game_odd.spread_point

    prob_home_covers = cover_probability(
      model_margin:,
      vegas_line: line,
      margin_std_deviation: stddev
    )

    recommend_home = prob_home_covers >= 0.5
    prob = recommend_home ? prob_home_covers : 1 - prob_home_covers
    odds = recommend_home ? game_odd.spread_home_odds : game_odd.spread_away_odds
    ev = expected_value(prob, odds)

    recommended = ev >= BETTING_CONFIG[:recommended_ev_threshold]
    team = if recommended
             recommend_home ? 'home' : 'away'
           end
    confidence = prob

    create_recommendation(
      game: @game,
      prediction:,
      game_odd:,
      bet_type: 'spread',
      team:,
      vegas_line: recommend_home ? line : -line,
      vegas_odds: odds,
      model_value: model_margin.round(2),
      confidence: confidence.round(3),
      ev: ev.round(4),
      recommended:
    )
  end

  def generate_moneyline_recommendation(prediction, game_odd)
    return unless game_odd.moneyline_home

    prob_home_wins = prediction.home_win_probability
    odds = game_odd.moneyline_home

    ev = expected_value(prob_home_wins, odds)

    recommended = ev >= BETTING_CONFIG[:recommended_ev_threshold]
    team = ('home' if recommended)
    confidence = prob_home_wins

    create_recommendation(
      game: @game,
      prediction:,
      game_odd:,
      bet_type: 'moneyline',
      team:,
      vegas_line: nil,
      vegas_odds: odds,
      model_value: prob_home_wins.round(3),
      confidence: confidence.round(3),
      ev: ev.round(4),
      recommended:
    )
  end

  def generate_total_recommendation(prediction, game_odd)
    return unless game_odd.total_points

    model_total = prediction.home_score + prediction.away_score
    stddev = prediction.total_std_deviation
    line = game_odd.total_points

    prob_over = cover_probability(
      model_margin: model_total,
      vegas_line: line,
      margin_std_deviation: stddev
    )

    recommend_over = prob_over >= 0.5
    prob = recommend_over ? prob_over : 1 - prob_over
    odds = recommend_over ? game_odd.total_over_odds : game_odd.total_under_odds
    ev = expected_value(prob, odds)

    recommended = ev >= BETTING_CONFIG[:recommended_ev_threshold]
    team = if recommended
             recommend_over ? 'over' : 'under'
           end
    confidence = prob

    create_recommendation(
      game: @game,
      prediction:,
      game_odd:,
      bet_type: 'total',
      team:,
      vegas_line: recommend_over ? line : -line,
      vegas_odds: odds,
      model_value: model_total.round(2),
      confidence: confidence.round(3),
      ev: ev.round(4),
      recommended:
    )
  end

  def cover_probability(model_margin:, vegas_line:, margin_std_deviation:)
    z_score = (model_margin - vegas_line) / margin_std_deviation

    StatisticsUtils.normal_cdf(z_score)
  end

  def expected_value(win_prob, odds)
    payout = odds.positive? ? odds / 100.0 : 100.0 / odds.abs
    ev = (win_prob * payout) - (1 - win_prob)
    ev.round(4)
  end

  def create_recommendation(**attrs)
    BetRecommendation.create!(
      **attrs,
      ratings_config_version: attrs[:prediction].ratings_config_version
    )
  end
end
