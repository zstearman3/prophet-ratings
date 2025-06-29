# frozen_string_literal: true

# Service to generate BetRecommendation rows for a game with a prediction and game odds
class BetRecommendationGenerator
  # Generates bet recommendations for a given game
  # @param game [Game] the game to generate recommendations for
  # @return [Array<BetRecommendation>] created recommendations
  def self.call(game:)
    prediction = game.current_prediction
    game_odd = game.game_odd
    recs = []

    recs << generate_spread_recommendation(game, prediction, game_odd)
    recs << generate_moneyline_recommendation(game, prediction, game_odd)
    recs << generate_total_recommendation(game, prediction, game_odd)

    recs
  end

  private

  def generate_spread_recommendation(_game, prediction, game_odd)
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

    recommended = ev >= 0.2
    team = if recommended
             recommend_home ? 'home' : 'away'
           end
    confidence = prob

    create_recommendation(
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

  def generate_moneyline_recommendation(_game, _prediction, _game_odd)
    pass
  end

  def generate_total_recommendation(_game, _prediction, _game_odd)
    pass
  end

  def cover_probability(model_margin:, vegas_line:, margin_std_deviation:)
    z_score = (model_margin - vegas_line) / margin_std_deviation

    Distribution::Normal.cdf(z_score)
  end

  def expected_value(win_prob, odds)
    payout = odds.positive? ? odds / 100.0 : 100.0 / odds.abs
    ev = (win_prob * payout) - (1 - win_prob)
    ev.round(4)
  end

  def create_recommendation(**attrs)
    BetRecommendation.create!(
      game:,
      prediction:,
      game_odd:,
      ratings_config_version: prediction.ratings_config_version,
      **attrs
    )
  end
end
