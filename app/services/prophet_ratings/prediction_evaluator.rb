# frozen_string_literal: true

module ProphetRatings
  # One forecast per game/model, with explicit provenance and no updates or solver runs.
  class PredictionEvaluator
    MODES = %w[pregame legacy_unverified reconstruction].freeze

    def initialize(ratings_config_version: RatingsConfigVersion.default_version,
                   date_range: Season.current.start_date..Season.current.end_date, mode: 'pregame', season: nil)
      raise ArgumentError, 'Unknown forecast type' unless MODES.include?(mode)

      @mode = mode
      @scope = Prediction.joins(:game).where(ratings_config_version:)
                         .merge(Game.final.through_schedule_date(date_range.end))
                         .where(games: { start_time: Game.schedule_day_range(date_range.begin).begin.. })
      @scope = @scope.where(games: { season_id: season.id }) if season
    end

    def call
      report.metrics.merge(coverage: coverage)
    end

    def report
      @report ||= EvaluationReport.new(observations)
    end

    def coverage
      selected_count = predictions.count
      evaluated_count = observations.size
      {
        mode: @mode, available_by_kind: @scope.group(:forecast_kind).count,
        selected: selected_count, evaluated: evaluated_count, excluded_invalid: selected_count - evaluated_count
      }
    end

    def observations
      @observations ||= predictions.includes(game: { home_team_game: :team, away_team_game: :team })
                                   .filter_map { |prediction| EvaluationObservation.new(prediction).call }
    end

    def compare(other)
      baseline = observations.index_by { |row| row.fetch(:game_id) }
      candidate = other.observations.index_by { |row| row[:game_id] }
      self.class.paired_metrics(baseline, candidate)
    end

    def self.paired_metrics(baseline, candidate)
      common_ids = baseline.keys & candidate.keys
      { games: common_ids.size, baseline: EvaluationReport.new(baseline.values_at(*common_ids)).metrics,
        candidate: EvaluationReport.new(candidate.values_at(*common_ids)).metrics }
    end

    def generate_pace_diagnostics(directory: Rails.root.join('tmp'))
      EvaluationCharts.new(report, directory:).pace
    end

    def generate_efficiency_diagnostics(directory: Rails.root.join('tmp'))
      EvaluationCharts.new(report, directory:).efficiency
    end

    private

    def predictions
      return @scope.selected_pregame if @mode == 'pregame'

      # Exploratory forecasts are deliberately separate from verified pregame performance.
      ids = @scope.where(forecast_kind: @mode)
                  .select('DISTINCT ON (game_id, ratings_config_version_id) predictions.id')
                  .order(:game_id, :ratings_config_version_id, generated_at: :desc, id: :desc)
      @scope.where(id: ids)
    end
  end
end
