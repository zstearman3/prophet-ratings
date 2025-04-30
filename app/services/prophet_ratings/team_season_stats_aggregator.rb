# frozen_string_literal: true

module ProphetRatings
  class TeamSeasonStatsAggregator
    AVERAGE_STATS = %i[
      turnover_rate offensive_rebound_rate free_throw_rate
      three_pt_attempt_rate offensive_efficiency defensive_efficiency
    ].freeze

    DERIVED_STATS = {
      effective_fg_percentage: ->(fgm:, fga:, three_pm:) {
        return nil if fga.zero?
        (fgm + 0.5 * three_pm) / fga.to_f
      }
    }.freeze

    def initialize(season: Season.current, as_of: Time.current)
      @season = season
      @as_of = as_of
    end

    def run
      preload_predictions
      TeamSeason
        .includes(team_games: :game)
        .where(season_id: @season.id)
        .where(game: { status: Game.statuses[:final], start_time: ..@as_of })
        .find_each do |team_season|

        aggregates = calculate_average_stats(team_season)
        aggregates.merge!(calculate_efficiency_stddevs(team_season))
        aggregates.merge!(calculate_volatility(team_season))
        aggregates.merge!(calculate_home_advantages(team_season))

        team_season.update_columns(aggregates) if aggregates.any?
      end
    end

    private

    attr_reader :season, :as_of, :home_preds_by_season, :away_preds_by_season

    def preload_predictions
      predictions = Prediction
        .joins(:game)
        .where(game: { start_time: ..as_of })
        .includes(:home_team_snapshot, :away_team_snapshot)
        .to_a

      @home_preds_by_season = predictions
        .select { |p| p.home_team_snapshot&.team_season_id }
        .group_by { |p| p.home_team_snapshot.team_season_id }

      @away_preds_by_season = predictions
        .select { |p| p.away_team_snapshot&.team_season_id }
        .group_by { |p| p.away_team_snapshot.team_season_id }
    end

    def calculate_average_stats(team_season)
      aggregates = {}

      AVERAGE_STATS.each do |stat|
        values = team_season.team_games.map { |g| g.send(stat) }.compact
        avg = values.sum / values.size.to_f if values.any?
        aggregates[stat] = avg
      end

      possession_vals = team_season.team_games.map { |g| g.game&.possessions }.compact
      aggregates[:pace] = possession_vals.sum / possession_vals.size.to_f if possession_vals.any?

      fgm = team_season.team_games.sum(&:field_goals_made)
      fga = team_season.team_games.sum(&:field_goals_attempted)
      three_pm = team_season.team_games.sum(&:three_pt_made)

      aggregates[:effective_fg_percentage] = DERIVED_STATS[:effective_fg_percentage].call(fgm: fgm, fga: fga, three_pm: three_pm)

      aggregates
    end

    def calculate_efficiency_stddevs(team_season)
      off_vals = team_season.team_games.map(&:offensive_efficiency).compact
      def_vals = team_season.team_games.map(&:defensive_efficiency).compact

      {
        offensive_efficiency_std_dev: StatisticsUtils.stddev(off_vals),
        defensive_efficiency_std_dev: StatisticsUtils.stddev(def_vals)
      }
    end

    def calculate_volatility(team_season)
      home_preds = home_preds_by_season[team_season.id] || []
      away_preds = away_preds_by_season[team_season.id] || []

      offensive_errors = home_preds.map(&:home_offensive_efficiency_error) + away_preds.map(&:away_offensive_efficiency_error)
      defensive_errors = home_preds.map(&:home_defensive_efficiency_error) + away_preds.map(&:away_defensive_efficiency_error)
      pace_errors = home_preds.map(&:pace_error) + away_preds.map(&:pace_error)

      {
        offensive_efficiency_volatility: StatisticsUtils.stddev(offensive_errors.compact),
        defensive_efficiency_volatility: StatisticsUtils.stddev(defensive_errors.compact),
        pace_volatility: StatisticsUtils.stddev(pace_errors.compact)
      }
    end

    def calculate_home_advantages(team_season)
      baseline = Rails.application.config_for(:ratings).home_court_advantage.to_f
      home_preds = (home_preds_by_season[team_season.id] || []).select { |p| !p.game.neutral? }
      return { home_offense_boost: baseline, home_defense_boost: -baseline } if home_preds.empty?

      off_deltas = home_preds.map(&:home_offensive_efficiency_error).compact
      def_deltas = home_preds.map(&:home_defensive_efficiency_error).compact

      avg_off = StatisticsUtils.average(off_deltas)
      avg_def = StatisticsUtils.average(def_deltas)
      weight = [(home_preds.size / 16.0), 0.50].min.round(4)

      blended_off = (weight * (avg_off + baseline)) + ((1.0 - weight) * baseline)
      blended_def = (weight * (avg_def - baseline)) - ((1.0 - weight) * baseline)

      {
        home_offense_boost: [blended_off, 0.0].max.round(3),
        home_defense_boost: [blended_def, 0.0].min.round(3)
      }
    end
  end
end
