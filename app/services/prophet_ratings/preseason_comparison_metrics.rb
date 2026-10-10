# frozen_string_literal: true

module ProphetRatings
  # Numerical errors and reliability bins; empty samples remain explicitly unknown.
  class PreseasonComparisonMetrics
    def initialize(rows)
      @rows = rows
    end

    def call
      {
        games: @rows.size,
        margin_mae: PreseasonComparisonMetrics.mean(margin_errors),
        total_mae: PreseasonComparisonMetrics.mean(total_errors),
        brier_score: PreseasonComparisonMetrics.mean(probability_errors),
        log_loss: self.class.mean(@rows.map { |row| PreseasonComparisonMetrics.log_loss(row) }),
        efficiency: error_report(:efficiency_errors), pace: error_report(:pace_errors),
        calibration: calibration_bins
      }
    end

    # Report exact impossible outcomes as Infinity; JSON exports use a string for portability.
    def self.log_loss(row)
      home_probability = row.fetch(:probability)
      probability = row.fetch(:outcome).positive? ? home_probability : 1 - home_probability
      probability.zero? ? Float::INFINITY : -Math.log(probability)
    end

    def error_report(key)
      values = @rows.flat_map { |row| row.fetch(key, []) }
      { observations: values.size, mae: self.class.mean(values.map(&:abs)) }
    end

    def self.pace_errors(actual, expected)
      actual&.finite? ? [expected - actual] : []
    end

    def self.mean(values)
      return if values.empty?
      return 'Infinity' if values.any?(&:infinite?)

      StatisticsUtils.average(values)
    end

    def margin_errors
      @rows.map { |row| row.fetch(:margin_error).abs }
    end

    def total_errors
      @rows.map { |row| row.fetch(:total_error).abs }
    end

    def probability_errors
      @rows.map { |row| self.class.probability_error(row) }
    end

    def self.probability_error(row)
      (row.fetch(:probability) - row.fetch(:outcome))**2
    end

    def calibration_bins
      @rows.group_by { |row| [(row.fetch(:probability) * 10).floor, 9].min }.sort.map do |bucket, members|
        self.class.bin_report(bucket, members)
      end
    end

    def self.bin_report(bucket, members)
      {
        lower: bucket / 10.0, upper: (bucket + 1) / 10.0, games: members.size,
        mean_probability: StatisticsUtils.average(members.pluck(:probability)),
        observed_home_win_rate: StatisticsUtils.average(members.pluck(:outcome))
      }
    end
    private :error_report, :margin_errors, :total_errors, :probability_errors, :calibration_bins
  end
end
