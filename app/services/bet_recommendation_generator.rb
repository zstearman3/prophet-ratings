# frozen_string_literal: true

# Service to generate BetRecommendation rows for a game with a prediction and game odds
class BetRecommendationGenerator
  BETTING_CONFIG = Rails.application.config_for(:betting).deep_symbolize_keys

  def self.call(game:)
    new(game).call
  end

  ##
  # Initializes a new BetRecommendationGenerator for the specified game.
  # @param [Game] game - The game for which to generate bet recommendations.
  def initialize(game)
    @game = game
  end

  # Generates bet recommendations for a given game
  # @param game [Game] the game to generate recommendations for
  ##
  # Generates bet recommendations for the game based on its current prediction and odds.
  # Returns an array of created recommendations for spread, moneyline, and total bet types.
  # @return [Array<BetRecommendation>] The generated bet recommendations (may include nils if data is insufficient).
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

  ##
  # Generates a spread bet recommendation for the given prediction and game odds.
  #
  # Calculates the probability and expected value for the home and away teams covering the spread,
  # recommends the side with probability ≥ 0.5, and flags the recommendation if the expected value meets the configured threshold.
  # Returns a BetRecommendation record or nil if spread data is unavailable.
  # @param prediction [Prediction] The prediction object containing model scores and standard deviation.
  # @param game_odd [GameOdd] The odds object containing spread line and odds.
  # @return [BetRecommendation, nil] The created or updated spread bet recommendation, or nil if insufficient data.
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

  ##
  # Generates a moneyline bet recommendation for the given prediction and game odds.
  #
  # Compares expected values for home and away moneyline bets based on the model's predicted home win probability and the available odds.
  # Recommends the side with the higher expected value, and flags the recommendation
  # if the expected value meets or exceeds the configured threshold.
  # Returns a BetRecommendation record or nil if neither moneyline odds are available.
  # @return [BetRecommendation, nil] The generated moneyline bet recommendation, or nil if insufficient odds are present.
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

  ##
  # Generates a bet recommendation for the total points (over/under) market based on the model's predicted total,
  # standard deviation, and available odds.
  # Returns a BetRecommendation record if sufficient data is present; otherwise, returns nil.
  # The recommendation includes selection ("over" or "under"), line, odds, model value, confidence, expected value,
  # and recommendation status.
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

  ##
  # Calculates the probability that the model margin exceeds the Vegas line using the normal distribution.
  # @param [Float] model_margin - The predicted margin from the model.
  # @param [Float] vegas_line - The Vegas betting line for the margin.
  # @param [Float] margin_std_deviation - The standard deviation of the predicted margin.
  # @return [Float] The probability that the model margin covers the Vegas line.
  def cover_probability(model_margin:, vegas_line:, margin_std_deviation:)
    z_score = (model_margin - vegas_line) / margin_std_deviation

    StatisticsUtils.normal_cdf(z_score)
  end

  ##
  # Calculates the expected value of a bet given the win probability and American odds.
  # Returns 0 if either value is missing or odds is zero.
  # @param [Float] win_prob - The probability of winning the bet (between 0 and 1).
  # @param [Integer] odds - The American odds for the bet.
  # @return [Float] The expected value, rounded to four decimal places.
  def expected_value(win_prob, odds)
    return 0 unless odds && win_prob && odds != 0

    payout = odds.positive? ? odds / 100.0 : 100.0 / odds.abs
    ev = (win_prob * payout) - (1 - win_prob)
    ev.round(4)
  end

  ##
  # Creates or updates a bet recommendation record for the current game and bet type with the provided attributes.
  # Marks existing recommendations of the same bet type as not current if the ratings configuration version is current.
  # @param attrs [Hash] Attributes for the recommendation, including bet type, prediction and odds IDs, team, line, odds,
  # model value, confidence, expected value, recommendation status, and ratings config version.
  # @return [BetRecommendation] The created or updated bet recommendation record.
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
