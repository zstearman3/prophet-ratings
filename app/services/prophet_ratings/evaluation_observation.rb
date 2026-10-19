# frozen_string_literal: true

module ProphetRatings
  # Recompute residuals from issued predictions and current finalized box scores, without writing either.
  class EvaluationObservation
    def initialize(prediction)
      @prediction = prediction
      @game = prediction.game
    end

    def call
      return if exclusion_reason

      {
        game_id: @game.id, prediction_id: @prediction.id, date: @game.schedule_date,
        probability: @prediction.home_win_probability.to_f, outcome: @game.home_team_score > @game.away_team_score ? 1.0 : 0.0,
        margin_error: margin_error, total_error: total_error,
        efficiency_errors: efficiency_errors.values.compact, side_errors: efficiency_errors,
        pace_errors: pace_pair ? [pace_pair.first - pace_pair.last] : [], pace_pair: pace_pair,
        margin_z: margin_z, teams: teams, factors: FactorEvaluation.observations(@prediction)
      }
    end

    def exclusion_reason
      return 'unmatched_result' if @game.final_unmatched?

      @prediction.participant_exclusion_reason || ('invalid_outcome' unless valid_outcome?)
    end

    def self.finite?(value)
      value.is_a?(Numeric) && value.finite?
    end

    private

    def teams
      [@game.home_team_game&.team, @game.away_team_game&.team].compact.map { |team| [team.id, team.school] }
    end

    def valid_outcome?
      probability = @prediction.home_win_probability
      home = @game.home_team_score
      away = @game.away_team_score
      [@prediction.home_score, @prediction.away_score, probability, home, away].all? { |value| EvaluationObservation.finite?(value) } &&
        (0..1).cover?(probability) && home != away
    end

    def margin_error
      (@prediction.home_score - @prediction.away_score - (@game.home_team_score - @game.away_team_score)).to_f
    end

    def total_error
      (@prediction.home_score + @prediction.away_score - (@game.home_team_score + @game.away_team_score)).to_f
    end

    def efficiency_errors
      @efficiency_errors ||= {
        home: EvaluationObservation.difference(@prediction.home_offensive_efficiency, @game.home_team_game&.offensive_efficiency),
        away: EvaluationObservation.difference(@prediction.away_offensive_efficiency, @game.away_team_game&.offensive_efficiency)
      }
    end

    public_class_method def self.difference(predicted, actual)
      (predicted - actual).to_f if [predicted, actual].all? { |value| EvaluationObservation.finite?(value) }
    end

    def pace_pair
      @pace_pair ||= begin
        predicted = @prediction.pace
        actual = @game.pace
        [predicted.to_f, actual.to_f] if [predicted, actual].all? { |value| EvaluationObservation.finite?(value) && value.positive? }
      end
    end

    def margin_z
      # Unverified legacy rows can depend on mutable snapshots: do not imply frozen uncertainty.
      return unless @prediction.calculation_context['contract_version'] == 1

      deviation = @prediction.margin_std_deviation
      margin_error / deviation if EvaluationObservation.finite?(deviation) && deviation.positive?
    rescue ArgumentError, KeyError, TypeError
      nil
    end
  end
end
