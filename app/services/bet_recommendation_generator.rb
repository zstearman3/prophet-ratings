# frozen_string_literal: true

# Service to generate BetRecommendation rows for a game with a prediction and game odds
class BetRecommendationGenerator
  # Generates bet recommendations for a given game
  # @param game [Game] the game to generate recommendations for
  # @param prediction [Prediction] the model prediction for the game
  # @param game_odd [GameOdd] the vegas odds for the game
  # @return [Array<BetRecommendation>] created recommendations
  def self.call(game:, prediction:, game_odd:)
    # Example logic: generate moneyline, spread, and total recommendations
    recs = []

    # Moneyline (home)
    if game_odd.moneyline_home && prediction.home_win_probability
      recs << create_recommendation(
        game: game,
        prediction: prediction,
        game_odd: game_odd,
        bet_type: 'moneyline',
        team: 'home',
        vegas_line: nil,
        vegas_odds: game_odd.moneyline_home,
        model_value: prediction.home_win_probability,
        ev: expected_value(prediction.home_win_probability, game_odd.moneyline_home),
        confidence: nil,
        recommended: false
      )
    end

    # Moneyline (away)
    if game_odd.moneyline_away && prediction.home_win_probability
      recs << create_recommendation(
        game: game,
        prediction: prediction,
        game_odd: game_odd,
        bet_type: 'moneyline',
        team: 'away',
        vegas_line: nil,
        vegas_odds: game_odd.moneyline_away,
        model_value: 1 - prediction.home_win_probability,
        ev: expected_value(1 - prediction.home_win_probability, game_odd.moneyline_away),
        confidence: nil,
        recommended: false
      )
    end

    # Spread (home)
    if game_odd.spread_point && game_odd.spread_home_odds && prediction.home_score && prediction.away_score
      model_spread = prediction.home_score - prediction.away_score
      recs << create_recommendation(
        game: game,
        prediction: prediction,
        game_odd: game_odd,
        bet_type: 'spread',
        team: 'home',
        vegas_line: game_odd.spread_point.to_f,
        vegas_odds: game_odd.spread_home_odds,
        model_value: model_spread,
        ev: nil,
        confidence: nil,
        recommended: false
      )
    end

    # Spread (away)
    if game_odd.spread_point && game_odd.spread_away_odds && prediction.home_score && prediction.away_score
      model_spread = prediction.away_score - prediction.home_score
      recs << create_recommendation(
        game: game,
        prediction: prediction,
        game_odd: game_odd,
        bet_type: 'spread',
        team: 'away',
        vegas_line: -game_odd.spread_point.to_f,
        vegas_odds: game_odd.spread_away_odds,
        model_value: model_spread,
        ev: nil,
        confidence: nil,
        recommended: false
      )
    end

    # Total (over)
    if game_odd.total_points && game_odd.total_over_odds && prediction.total
      recs << create_recommendation(
        game: game,
        prediction: prediction,
        game_odd: game_odd,
        bet_type: 'total',
        team: 'over',
        vegas_line: game_odd.total_points.to_f,
        vegas_odds: game_odd.total_over_odds,
        model_value: prediction.total,
        ev: nil,
        confidence: nil,
        recommended: false
      )
    end

    # Total (under)
    if game_odd.total_points && game_odd.total_under_odds && prediction.total
      recs << create_recommendation(
        game: game,
        prediction: prediction,
        game_odd: game_odd,
        bet_type: 'total',
        team: 'under',
        vegas_line: game_odd.total_points.to_f,
        vegas_odds: game_odd.total_under_odds,
        model_value: prediction.total,
        ev: nil,
        confidence: nil,
        recommended: false
      )
    end

    recs
  end

  # Calculate expected value for a bet
  # win_prob: model probability of winning (0-1)
  # odds: American odds
  def self.expected_value(win_prob, odds)
    payout = odds > 0 ? odds / 100.0 : 100.0 / odds.abs
    ev = win_prob * payout - (1 - win_prob)
    ev.round(4)
  end

  def self.create_recommendation(**attrs)
    BetRecommendation.create!(attrs)
  end
end
