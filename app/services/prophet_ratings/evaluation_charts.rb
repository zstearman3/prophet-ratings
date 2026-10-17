# frozen_string_literal: true

require 'fileutils'

module ProphetRatings
  # Optional offline PNG compatibility. The admin page uses Chartkick, not ImageMagick.
  class EvaluationCharts
    def initialize(report, directory:)
      require 'gruff'
      @report = report
      @directory = Pathname.new(directory)
      FileUtils.mkdir_p(@directory)
    end

    def pace
      scatter('predicted_vs_actual_pace', 'Predicted vs Actual Pace (per 40 minutes)', @report.pace_pairs)
      scatter('pace_residuals_vs_predicted', 'Pace Error vs Predicted Pace (Predicted - Actual)', @report.pace_residual_pairs)
      histogram('pace_residuals_histogram', 'Pace Error (Predicted - Actual)', EvaluationReport.histogram(@report.residuals[:pace]))
    end

    def efficiency
      %i[home away].each do |side|
        histogram("#{side}_off_eff_residuals", "#{side.capitalize} Efficiency Error (Predicted - Actual)",
                  EvaluationReport.histogram(@report.residuals[side]))
      end
      histogram('z_score_histogram', 'Standardized Margin Error (Predicted - Actual)', @report.z_histogram)
      calibration
      @directory.join('team_residuals.csv').write(@report.team_csv)
    end

    private

    def scatter(name, title, pairs)
      save(name, EvaluationCharts.scatter_chart(title, pairs)) if pairs.any?
    end

    def histogram(name, title, counts)
      save(name, EvaluationCharts.bar_chart(title, counts)) if counts.any?
    end

    def calibration
      bins = @report.calibration
      save('win_prob_calibration', EvaluationCharts.calibration_chart(bins)) if bins.any?
    end

    def save(name, chart)
      chart.write(@directory.join("#{name}.png").to_s)
    end

    public_class_method def self.scatter_chart(title, pairs)
      Gruff::Scatter.new.tap do |chart|
        chart.title = title
        chart.data(:Games, pairs.map(&:first), pairs.map(&:last))
      end
    end

    public_class_method def self.bar_chart(title, counts)
      Gruff::Bar.new.tap do |chart|
        chart.title = title
        chart.labels = counts.keys.each_with_index.to_h { |value, index| [index, value.to_s] }
        chart.data(:Games, counts.values)
      end
    end

    public_class_method def self.calibration_chart(bins)
      Gruff::Line.new.tap do |chart|
        chart.labels = bins.each_with_index.to_h { |bin, index| [index, "#{bin[:lower]} (n=#{bin[:games]})"] }
        chart.data('Mean predicted probability', bins.pluck(:mean_probability))
        chart.data('Observed win rate', bins.pluck(:observed_home_win_rate))
      end
    end
  end
end
