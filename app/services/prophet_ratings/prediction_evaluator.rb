# frozen_string_literal: true

module ProphetRatings
  class PredictionEvaluator
    def initialize(
      ratings_config_version: RatingsConfigVersion.current,
      date_range: Season.current.start_date..Season.current.end_date
    )

      @predictions = Prediction
                     .joins(:home_team_snapshot, :game)
                     .where(home_team_snapshot: { ratings_config_version_id: ratings_config_version.id })
                     .where(games: { start_time: date_range })
    end

    def call
      {
        overall_mae: calculate_overall_mae,
        average_biases: calculate_biases,
        stddev_of_errors: calculate_stddevs,
        prediction_accuracy: calculate_prediction_accuracy
      }
    end

    def generate_pace_diagnostics
      plot_pace_scatterplot
      plot_pace_residuals_histogram
      plot_residuals_vs_predicted_pace
    end

    def generate_efficiency_diagnostics
      plot_efficiency_error_histograms
      plot_win_prob_calibration
      export_team_residuals_to_csv
    end

    private

    attr_reader :predictions

    def calculate_overall_mae
      {
        pace_error_mae: StatisticsUtils.mae(predictions.pluck(:pace_error)),
        home_off_mae: StatisticsUtils.mae(predictions.pluck(:home_offensive_efficiency_error)),
        away_off_mae: StatisticsUtils.mae(predictions.pluck(:away_offensive_efficiency_error))
      }
    end

    def calculate_biases
      {
        pace_error_avg: StatisticsUtils.average(predictions.pluck(:pace_error)),
        home_off_avg: StatisticsUtils.average(predictions.pluck(:home_offensive_efficiency_error)),
        away_off_avg: StatisticsUtils.average(predictions.pluck(:away_offensive_efficiency_error))
      }
    end

    def calculate_stddevs
      {
        pace_error_stddev: StatisticsUtils.stddev(predictions.pluck(:pace_error)),
        home_off_stddev: StatisticsUtils.stddev(predictions.pluck(:home_offensive_efficiency_error)),
        away_off_stddev: StatisticsUtils.stddev(predictions.pluck(:away_offensive_efficiency_error))
      }
    end

    def calculate_prediction_accuracy
      total = 0
      correct = 0

      predictions.each do |p|
        next unless p.home_win_probability && p.game&.home_team_score && p.game&.away_team_score

        predicted_home_win = p.home_win_probability >= 0.5
        actual_home_win = p.game.home_team_score > p.game.away_team_score

        total += 1
        correct += 1 if predicted_home_win == actual_home_win
      end

      accuracy = total.positive? ? correct.to_f / total : nil
      {
        total_predictions: total,
        correct_predictions: correct,
        prediction_accuracy: accuracy
      }
    end

    def plot_pace_scatterplot
      require 'gruff'

      g = Gruff::Scatter.new
      g.title = 'Predicted vs Actual Pace'

      x_values = []
      y_values = []

      @predictions.each do |prediction|
        next unless prediction.pace && prediction.game&.possessions

        x_values << prediction.pace.to_f.round(2) # predicted
        y_values << prediction.game.possessions.to_f.round(2) # actual
      end

      g.data(:Games, x_values, y_values)
      g.minimum_value = [x_values.min, y_values.min].min.floor - 5
      g.maximum_value = [x_values.max, y_values.max].max.ceil + 5
      g.write('tmp/predicted_vs_actual_pace.png')

      Rails.logger.debug '📈 Saved scatterplot to tmp/predicted_vs_actual_pace.png'
    end

    def plot_pace_residuals_histogram
      require 'gruff'

      g = Gruff::Bar.new
      g.title = 'Pace Prediction Residuals (Actual - Predicted)'

      residuals = @predictions.filter_map do |prediction|
        next unless prediction.pace && prediction.game&.possessions

        (prediction.game.possessions.to_f - prediction.pace.to_f).round(2)
      end

      # Group residuals into buckets
      bucketed = residuals.group_by { |r| (r / 2.0).round * 2 } # every 2 possessions
      sorted_buckets = bucketed.sort_by { |bucket, _| bucket }

      labels = {}
      counts = []
      sorted_buckets.each_with_index do |(bucket, values), idx|
        labels[idx] = bucket
        counts << values.size
      end

      g.labels = labels
      g.data(:Residuals, counts)
      g.write('tmp/pace_residuals_histogram.png')

      Rails.logger.debug '📊 Saved residuals histogram to tmp/pace_residuals_histogram.png'
    end

    def plot_efficiency_error_histograms
      require 'gruff'

      { home: :home_offensive_efficiency_error, away: :away_offensive_efficiency_error }.each do |label, column|
        g = Gruff::Bar.new
        g.title = "#{label.capitalize} Offensive Efficiency Residuals"

        errors = predictions.pluck(column).compact.map(&:to_f)
        buckets = errors.group_by { |e| (e / 2.0).round * 2 }
        sorted = buckets.sort_by(&:first)

        labels = {}
        counts = []
        sorted.each_with_index do |(bucket, values), i|
          labels[i] = bucket
          counts << values.size
        end

        g.labels = labels
        g.data(:Residuals, counts)
        g.write("tmp/#{label}_off_eff_residuals.png")
      end
    end

    def plot_residuals_vs_predicted_pace
      require 'gruff'
      g = Gruff::Scatter.new
      g.title = 'Pace Residual vs Predicted Pace'

      x = []
      y = []

      predictions.each do |p|
        next unless p.pace && p.game&.possessions

        x << p.pace.to_f
        y << (p.game.possessions.to_f - p.pace.to_f).round(2)
      end

      g.data(:Games, x, y)
      g.write('tmp/pace_residuals_vs_predicted.png')
    end

    def plot_win_prob_calibration
      require 'gruff'
      g = Gruff::Line.new
      g.title = 'Win Probability Calibration'

      bucket_size = 0.05
      buckets = Hash.new { |h, k| h[k] = [] }

      predictions.each do |p|
        next unless p.home_win_probability && p.game&.home_team_score && p.game&.away_team_score

        predicted = p.home_win_probability.to_f
        next if predicted.nan? || predicted.infinite?

        actual = if p.game.home_team_score > p.game.away_team_score
                   1.0
                 elsif p.game.home_team_score < p.game.away_team_score
                   0.0
                 else
                   next # skip ties or missing scores
                 end

        bucket = (predicted / bucket_size).floor * bucket_size
        buckets[bucket] << actual
      end

      sorted = buckets.sort_by(&:first)
      labels = {}
      predicted_probs = []
      actual_probs = []

      sorted.each_with_index do |(predicted_bucket, outcomes), i|
        next if outcomes.size < 10 # skip sparse buckets

        labels[i] = predicted_bucket.round(2).to_s
        predicted_probs << predicted_bucket.round(2)
        actual_probs << (outcomes.sum.to_f / outcomes.size).round(3)
      end

      g.labels = labels
      g.data('Actual Win %', actual_probs)
      g.write('tmp/win_prob_calibration.png')
    end

    def export_team_residuals_to_csv(path: 'tmp/team_residuals.csv')
      team_data = Hash.new { |h, k| h[k] = [] }

      predictions.each do |p|
        next unless p.game&.home_team_season&.team && p.game&.away_team_season&.team
        next unless p.pace && p.game.possessions

        residual = p.game.possessions.to_f - p.pace.to_f

        home_team = p.game.home_team_season.team.school
        away_team = p.game.away_team_season.team.school

        team_data[home_team] << residual
        team_data[away_team] << (-1 * residual)
      end

      CSV.open(path, 'w') do |csv|
        csv << %w[team_id games avg_pace_residual stddev_pace_residual]
        team_data.each do |team_id, residuals|
          next if residuals.empty?

          avg = StatisticsUtils.average(residuals)
          stddev = StatisticsUtils.stddev(residuals)
          csv << [team_id, residuals.size, avg.round(2), stddev.round(2)]
        end
      end

      Rails.logger.debug { "📁 Exported team residuals to #{path}" }
    end
  end
end
