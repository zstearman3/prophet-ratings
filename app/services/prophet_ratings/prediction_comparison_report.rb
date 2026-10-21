# frozen_string_literal: true

require 'csv'

module ProphetRatings
  # Illustrative comparison of saved forecasts, including separately selected provenance types.
  class PredictionComparisonReport
    def initialize(season:, baseline:, candidate:, **options)
      @models = { baseline:, candidate: }
      @modes = { baseline: options.fetch(:baseline_mode, 'legacy_unverified'),
                 candidate: options.fetch(:candidate_mode, 'reconstruction') }
      @dates = self.class.date_range(season, options)
      @evaluators = @models.to_h do |role, model|
        [role, PredictionEvaluator.new(season:, ratings_config_version: model, date_range: @dates, mode: @modes.fetch(role))]
      end
    end

    def self.date_range(season, options)
      bounds = season.start_date..season.end_date
      first = Date.iso8601(options.fetch(:from, bounds.begin.iso8601))
      last = Date.iso8601(options.fetch(:through, bounds.end.iso8601))
      unless first <= last && bounds.cover?(first) && bounds.cover?(last)
        raise ArgumentError, 'Choose an ordered date range within the selected season'
      end

      first..last
    end

    def comparison
      @comparison ||= @evaluators.fetch(:baseline).compare(@evaluators.fetch(:candidate))
    end

    def text
      lines = ['Illustrative only: saved legacy forecasts and reconstructions do not establish live predictive performance.',
               "Eastern game dates: #{@dates.begin} through #{@dates.end}", *coverage_lines,
               "Common valid games: #{comparison.fetch(:games)}", 'All summary metrics below use only those common games.',
               'Bias = predicted minus actual. Efficiency is points/100 possessions; pace is possessions/40 minutes.',
               "Metric\tBaseline\tCandidate", *metric_lines]
      lines << 'No common valid games. Check the model versions, forecast types, date range and completed rerun.' if common_ids.empty?
      lines << 'Actuals use current finalized results; source corrections can change this report.'
      lines.join("\n")
    end

    def csv
      header = %w[game_id date home_team away_team role model forecast_type prediction_id margin_absolute_error
                  total_absolute_error home_score_absolute_error away_score_absolute_error pace_absolute_error
                  home_efficiency_absolute_error away_efficiency_absolute_error brier_score log_loss]
      rows = common_ids.flat_map { |id| csv_rows(id) }
      ([header] + rows).map { |values| CSV.generate_line(values) }.join
    end

    private

    def indexed_rows
      @indexed_rows ||= @evaluators.transform_values { |evaluator| self.class.index(evaluator) }
    end

    public_class_method def self.index(evaluator)
      evaluator.observations.index_by { |row| row.fetch(:game_id) }
    end

    def common_ids
      @common_ids ||= begin
        baseline = indexed_rows.fetch(:baseline)
        (baseline.keys & indexed_rows.fetch(:candidate).keys).sort_by { |id| [baseline.fetch(id).fetch(:date), id] }
      end
    end

    def coverage_lines
      @evaluators.map do |role, evaluator|
        coverage = evaluator.coverage
        valid = coverage[:evaluated]
        "#{role.capitalize}: #{@models.fetch(role).name} [#{@modes.fetch(role)}]; " \
          "selected=#{coverage[:selected]}, valid=#{valid}, excluded_invalid=#{coverage[:excluded_invalid]}, " \
          "valid_without_counterpart=#{valid - common_ids.size}"
      end
    end

    def metric_lines
      primary = %i[margin_mae total_mae brier_score log_loss].map { |key| metric_line(key, [key]) }
      residuals = %i[pace home away margin total].flat_map { |outcome| residual_lines(outcome) }
      primary + [metric_line('winner_accuracy', %i[prediction_accuracy prediction_accuracy])] + residuals
    end

    def residual_lines(outcome)
      label = { home: 'home_efficiency', away: 'away_efficiency' }.fetch(outcome, outcome)
      %i[observations mae rmse bias].map { |metric| metric_line("#{label}_#{metric}", [:residuals, outcome, metric]) }
    end

    def metric_line(label, path)
      values = @models.keys.map { |role| self.class.format_metric(comparison.fetch(role).dig(*path)) }
      ([label] + values).join("\t")
    end

    public_class_method def self.format_metric(value)
      case value
      when NilClass then 'N/A'
      when Float then format('%.6f', value)
      else value.to_s
      end
    end

    def csv_rows(id)
      @models.map do |role, model|
        metadata = [role, model.name, @modes.fetch(role)]
        self.class.csv_row(indexed_rows.fetch(role).fetch(id), metadata)
      end
    end

    public_class_method def self.csv_row(row, metadata)
      margin, total = row.values_at(:margin_error, :total_error)
      home, away = row.fetch(:teams).map(&:last)
      [row.fetch(:game_id), row.fetch(:date), home, away, *metadata,
       row.fetch(:prediction_id), margin.abs, total.abs, ((total + margin) / 2).abs, ((total - margin) / 2).abs,
       row.fetch(:pace_errors).first&.abs, row.dig(:side_errors, :home)&.abs, row.dig(:side_errors, :away)&.abs,
       PreseasonComparisonMetrics.probability_error(row), PreseasonComparisonMetrics.log_loss(row)]
    end
  end
end
