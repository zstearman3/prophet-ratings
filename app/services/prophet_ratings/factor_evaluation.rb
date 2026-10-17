# frozen_string_literal: true

module ProphetRatings
  # Compare issued factor forecasts with finalized results on matching observations.
  class FactorEvaluation
    def self.observations(prediction)
      forecasts = prediction.calculation_context.fetch('factor_forecasts', {})
      forecasts.to_h { |name, forecast| [name, pairs(prediction.game, name, forecast)] }
    end

    def self.pairs(game, name, forecast)
      { 'home' => game.home_team_game, 'away' => game.away_team_game }.filter_map do |side, team_game|
        observation(forecast, side, actual(team_game, name))
      end
    end

    def self.actual(team_game, name)
      return unless team_game && FactorForecast::FIELDS.key?(name.to_sym)
      return team_game.calculated_three_pt_proficiency if name == 'three_pt_proficiency'

      team_game.public_send(name)
    end

    def self.observation(forecast, side, actual)
      predicted = forecast[side]
      baseline = forecast['baseline']
      return unless [predicted, baseline, actual].all? { |value| EvaluationObservation.finite?(value) }

      { predicted:, actual:, error: predicted - actual, baseline_error: baseline - actual }
    end

    def self.summary(observations)
      { model: EvaluationReport.summary(observations.pluck(:error)),
        baseline: EvaluationReport.summary(observations.pluck(:baseline_error)) }
    end
  end
end
