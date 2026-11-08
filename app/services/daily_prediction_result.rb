# frozen_string_literal: true

# Straight-up result for exactly the forecast shown in the daily row.
class DailyPredictionResult
  def initialize(game, prediction)
    @game = game
    @prediction = prediction
  end

  def status
    return 'excluded' if reason
    return 'pending' unless @game.final?

    predicted_home_win? == (@game.home_team_score > @game.away_team_score) ? 'correct' : 'incorrect'
  end

  def reason
    forecast_exclusion || ('Canceled game' if @game.canceled?) ||
      (ProphetRatings::EvaluationObservation.new(@prediction).exclusion_reason if @game.final?)
  end

  def forecast_exclusion
    return 'Source result is ungraded' if source_result?
    return 'No verified pregame forecast' unless @prediction&.forecast_kind == 'pregame'
    return 'Unmatched result' if @game.final_unmatched?

    @prediction.participant_exclusion_reason || provenance_exclusion
  end

  def winner
    return unless probability

    predicted_home_win? ? @game.home_team_name : @game.away_team_name
  end

  def probability
    value = @prediction&.home_win_probability
    [value, 1 - value].max if ProphetRatings::EvaluationObservation.finite?(value) && (0..1).cover?(value)
  end

  def source_result?
    @game.is_a?(GameResultPresenter) || @game.is_a?(GameResultPresenter::UnavailableResult)
  end

  private

  def predicted_home_win?
    @prediction.home_win_probability >= 0.5
  end

  def provenance_exclusion
    return 'Invalid model probability' unless probability
    return if BetRecommendationIssue.verified_forecast?(@game, @prediction, @prediction.generated_at)

    'Invalid pregame provenance'
  end
end
