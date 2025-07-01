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

    return [] if prediction.nil? || game_odd.nil?

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
      vegas_line: -line,
      margin_std_deviation: stddev
    )

    recommend_home = prob_home_covers >= 0.5
    prob = recommend_home ? prob_home_covers : 1 - prob_home_covers
    odds = (recommend_home ? game_odd.spread_home_odds : game_odd.spread_away_odds) || -110
    ev = expected_value(prob, odds)

    recommended = ev >= BETTING_CONFIG[:recommended_ev_threshold]
    team = if recommended
             recommend_home ? 'home' : 'away'
           end
    confidence = prob

    create_recommendation(
      bet_type: 'spread',
      prediction_id: prediction.id,
      game_odd_id: game_odd.id,
      ratings_config_version_id: prediction.ratings_config_version_id,
      ratings_config_version_current: prediction.ratings_config_version.current,
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
    return unless game_odd.moneyline_home || game_odd.moneyline_away

    prob_home_wins = prediction.home_win_probability

    home_ev = game_odd.moneyline_home ? expected_value(prob_home_wins, game_odd.moneyline_home) : 0
    away_ev = game_odd.moneyline_away ? expected_value(1 - prob_home_wins, game_odd.moneyline_away) : 0

    recommend_home = home_ev > away_ev
    prob = recommend_home ? prob_home_wins : 1 - prob_home_wins
    odds = recommend_home ? game_odd.moneyline_home : game_odd.moneyline_away
    ev = recommend_home ? home_ev : away_ev

    recommended = ev >= BETTING_CONFIG[:recommended_ev_threshold]
    team = recommend_home ? 'home' : 'away'
    confidence = prob

    create_recommendation(
      bet_type: 'moneyline',
      prediction_id: prediction.id,
      game_odd_id: game_odd.id,
      ratings_config_version_id: prediction.ratings_config_version_id,
      ratings_config_version_current: prediction.ratings_config_version.current,
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
    return if stddev.nil? || stddev.zero?

    line = game_odd.total_points

    prob_over = cover_probability(
      model_margin: model_total,
      vegas_line: line,
      margin_std_deviation: stddev
    )

    recommend_over = prob_over >= 0.5
    prob = recommend_over ? prob_over : (1 - prob_over)
    odds = (recommend_over ? game_odd.total_over_odds : game_odd.total_under_odds) || -110
    ev = expected_value(prob, odds)

    recommended = ev >= BETTING_CONFIG[:recommended_ev_threshold]
    selection = recommend_over ? 'over' : 'under'

    create_recommendation(
      bet_type: 'total',
      prediction_id: prediction.id,
      game_odd_id: game_odd.id,
      ratings_config_version_id: prediction.ratings_config_version_id,
      ratings_config_version_current: prediction.ratings_config_version.current,
      team: (recommended ? selection : nil),
      vegas_line: line,
      vegas_odds: odds,
      model_value: model_total.round(2),
      confidence: prob.round(3),
      ev: ev.round(4),
      recommended:
    )
  end

  def cover_probability(model_margin:, vegas_line:, margin_std_deviation:)
    z_score = (model_margin - vegas_line) / margin_std_deviation

    StatisticsUtils.normal_cdf(z_score)
  end

  def expected_value(win_prob, odds)
    return 0 unless odds && win_prob && odds != 0

    payout = odds.positive? ? odds / 100.0 : 100.0 / odds.abs
    ev = (win_prob * payout) - (1 - win_prob)
    ev.round(4)
  end

  def create_recommendation(**attrs)
    BetRecommendation.where(game: @game, bet_type: attrs[:bet_type]).update_all(current: false) if attrs[:ratings_config_version_current]

    rec = BetRecommendation.find_or_initialize_by(
      bet_type: attrs[:bet_type],
      prediction_id: attrs[:prediction_id],
      game_odd_id: attrs[:game_odd_id]
    )
    rec.assign_attributes(
      game: @game,
      ratings_config_version_id: attrs[:ratings_config_version_id],
      team: attrs[:team],
      vegas_line: attrs[:vegas_line],
      vegas_odds: attrs[:vegas_odds],
      model_value: attrs[:model_value],
      confidence: attrs[:confidence],
      ev: attrs[:ev],
      recommended: attrs[:recommended],
      current: attrs[:ratings_config_version_current]
    )
    rec.save!
    rec
  end
end
