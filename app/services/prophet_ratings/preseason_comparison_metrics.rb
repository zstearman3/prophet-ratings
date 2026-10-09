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
        calibration: calibration_bins
      }
    end

    def self.mean(values)
      StatisticsUtils.average(values) unless values.empty?
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
    private :margin_errors, :total_errors, :probability_errors, :calibration_bins
  end
end
