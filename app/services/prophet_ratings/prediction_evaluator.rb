# frozen_string_literal: true

module ProphetRatings
  # One forecast per game/model, with explicit provenance and no updates or solver runs.
  class PredictionEvaluator
    MODES = %w[pregame legacy_unverified reconstruction].freeze

    def initialize(ratings_config_version: RatingsConfigVersion.default_version,
                   date_range: Season.current.start_date..Season.current.end_date, mode: 'pregame', season: nil)
      raise ArgumentError, 'Unknown forecast type' unless MODES.include?(mode)

      @excluded_by_reason = Hash.new(0)
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
        selected: selected_count, evaluated: evaluated_count, excluded_invalid: selected_count - evaluated_count,
        excluded_by_reason: @excluded_by_reason
      }
    end

    def observations
      @observations ||= begin
        @excluded_by_reason = Hash.new(0)
        predictions.includes(:home_team_snapshot, :away_team_snapshot,
                             game: { home_team_game: :team, away_team_game: :team }).filter_map do |prediction|
          observation_for(prediction)
        end
      end
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

    def observation_for(prediction)
      result = EvaluationObservation.new(prediction).call
      @excluded_by_reason[prediction.participant_exclusion_reason || 'invalid_outcome'] += 1 unless result
      result
    end

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
