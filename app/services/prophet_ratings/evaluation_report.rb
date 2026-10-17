# frozen_string_literal: true

require 'csv'

module ProphetRatings
  # Shared numerical data for browser charts and optional PNG exports.
  class EvaluationReport
    attr_reader :rows

    def initialize(rows)
      @rows = rows
    end

    def metrics
      metrics = PreseasonComparisonMetrics.new(rows).call
      summaries = residuals.transform_values { |values| EvaluationReport.summary(values) }
      metrics.merge(residuals: summaries, prediction_accuracy: accuracy).merge(EvaluationReport.legacy_statistics(summaries))
    end

    def self.legacy_statistics(summaries)
      pace, home, away = summaries.values_at(:pace, :home, :away)
      {
        overall_mae: { pace_error_mae: pace[:mae], home_off_mae: home[:mae], away_off_mae: away[:mae] },
        average_biases: { pace_error_avg: pace[:bias], home_off_avg: home[:bias], away_off_avg: away[:bias] },
        stddev_of_errors: { pace_error_stddev: pace[:sd], home_off_stddev: home[:sd], away_off_stddev: away[:sd] }
      }
    end

    def self.summary(values)
      return { observations: 0, mae: nil, bias: nil, sd: nil, rmse: nil } if values.empty?

      { observations: values.size, mae: StatisticsUtils.mae(values), bias: StatisticsUtils.average(values),
        sd: values.many? ? StatisticsUtils.stddev(values) : nil,
        rmse: Math.sqrt(StatisticsUtils.average(values.map { |value| value**2 })) }
    end

    def residuals
      {
        pace: rows.flat_map { |row| row.fetch(:pace_errors) },
        home: side_errors(:home), away: side_errors(:away),
        margin: rows.pluck(:margin_error), total: rows.pluck(:total_error)
      }
    end

    def factor_observations
      FactorForecast::FIELDS.keys.index_with do |name|
        observations_for_factor(name)
      end
    end

    def observations_for_factor(name)
      rows.flat_map { |row| row.fetch(:factors, {}).fetch(name.to_s, []) }
    end

    def factor_metrics
      factor_observations.transform_values { |observations| FactorEvaluation.summary(observations) }
    end

    def pace_pairs
      rows.filter_map { |row| row[:pace_pair] }
    end

    def pace_residual_pairs
      pace_pairs.map { |predicted, actual| [predicted, predicted - actual] }
    end

    def self.histogram(values, width: 2.0)
      values.group_by { |value| (value / width).round * width }.sort.to_h.transform_values(&:size)
    end

    def z_histogram
      EvaluationReport.histogram(rows.filter_map { |row| row[:margin_z] }, width: 0.5)
    end

    def calibration
      PreseasonComparisonMetrics.new(rows).call.fetch(:calibration)
    end

    def team_residuals
      summaries = team_groups.map { |id, games| EvaluationReport.team_summary(id, games) }
      summaries.sort_by { |team| team[:school] }
    end

    def self.team_entries(row)
      errors = row.fetch(:pace_errors)
      row.fetch(:teams).map { |id, school| { id:, school:, errors: } }
    end

    def self.team_summary(id, games)
      { id:, school: games.first.fetch(:school) }.merge(summary(games.flat_map { |game| game[:errors] }))
    end

    def team_csv
      header = CSV.generate_line(%w[team_id school games avg_pace_residual stddev_pace_residual])
      header + team_residuals.map { |team| CSV.generate_line(team.values_at(:id, :school, :observations, :bias, :sd)) }.join
    end

    private

    def team_groups
      rows.flat_map { |row| EvaluationReport.team_entries(row) }.group_by { |entry| entry[:id] }
    end

    def side_errors(side)
      rows.filter_map { |row| row.dig(:side_errors, side) }
    end

    def accuracy
      count = rows.size
      correct = rows.count { |row| (row.fetch(:probability) >= 0.5) == row.fetch(:outcome).positive? }
      { total_predictions: count, correct_predictions: correct, prediction_accuracy: count.positive? ? correct.to_f / count : nil }
    end
  end
end
