# frozen_string_literal: true

# Select one complete issue before validating it, never an older actionable pick.
class DailyPredictionPerformance
  attr_reader :game, :prediction, :issue, :straight_up

  def initialize(game, ratings_config_version:)
    @game = game
    @prediction = game.historical_prediction(ratings_config_version:) || game.current_prediction(ratings_config_version:)
    @straight_up = DailyPredictionResult.new(game, prediction)
    @issue = selected_issue
  end

  def betting_prediction = (prediction unless display_excluded?)

  def identity = [game.id, prediction&.ratings_config_version_id]

  def markets
    @markets ||= BetRecommendationIssue::MARKETS.index_with do |market|
      DailyBetResult.new(game, recommendations[market], market_exclusion)
    end
  end

  def recommendations
    @recommendations ||= if display_excluded?
                           {}
                         elsif issue
                           saved_recommendations
                         else
                           legacy_recommendations
                         end
  end

  private

  def display_excluded?
    straight_up.source_result? || prediction&.participant_exclusion_reason ||
      (issue && issue.evidence['participants'] != BetRecommendationIssue.participant_identities(game))
  end

  def selected_issue
    return unless prediction && !straight_up.source_result?

    game.bet_recommendation_issues.select { |saved| saved.prediction_id == prediction.id }
        .max_by { |saved| [saved.issued_at, saved.id] }
  end

  def saved_recommendations
    evidence = issue.evidence
    evidence.fetch('markets', {}).filter_map do |market, saved|
      if saved
        [market,
         SavedBetRecommendation.new(saved.merge('team_names' => evidence['team_names']), game:, prediction:, bet_type: market)]
      end
    end.to_h
  end

  def legacy_recommendations
    game.current_bet_recommendations.select do |rec|
      rec.usable_for_forecast?(prediction)
    end.index_by(&:bet_type)
  end

  def market_exclusion
    straight_up.forecast_exclusion || issue_exclusion ||
      (ProphetRatings::EvaluationObservation.new(prediction).exclusion_reason if game.final?)
  end

  def issue_exclusion
    return 'Legacy recommendation has no saved pregame issue' unless issue

    issue.exclusion_reason(game, prediction)
  end
end
