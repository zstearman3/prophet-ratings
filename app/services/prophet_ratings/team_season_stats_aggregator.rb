# frozen_string_literal: true

module ProphetRatings
  class TeamSeasonStatsAggregator
    AVERAGE_STATS = %i[
      turnover_rate
      offensive_rebound_rate
      free_throw_rate
      three_pt_attempt_rate
      offensive_efficiency
      defensive_efficiency
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
      off_stdevs = []
      def_stdevs = []
    
      TeamSeason
      .includes(team_games: { game: :predictions })
      .where(season_id: @season.id)
      .where(game: { status: Game.statuses[:final], start_time: ..@as_of })
      .find_each do |team_season|
    
        aggregates = calculate_average_stats(team_season)
        aggregates.merge!(calculate_efficiency_stddevs(team_season))
        aggregates.merge!(calculate_volatility(team_season))
    
        off_stdevs << aggregates[:off_efficiency_std_deviation]
        def_stdevs << aggregates[:def_efficiency_std_deviation]
    
        team_season.update_columns(aggregates) if aggregates.any?
      end
    end

    private

    attr_reader :season

    def calculate_average_stats(team_season)
      aggregates = {}
    
      AVERAGE_STATS.each do |stat|
        values = team_season.team_games.map { |g| g.send(stat) }.compact
        avg = values.sum / values.size.to_f if values.any?
        aggregates[stat] = avg
      end

      possession_vals = team_season.team_games.map { |g| g.game&.possessions }.compact
      if possession_vals.any?
        avg_possessions = possession_vals.sum / possession_vals.size.to_f
        aggregates[:pace] = avg_possessions
      end
    
      fgm = team_season.team_games.sum(&:field_goals_made)
      fga = team_season.team_games.sum(&:field_goals_attempted)
      three_pm = team_season.team_games.sum(&:three_pt_made)
    
      aggregates[:effective_fg_percentage] = DERIVED_STATS[:effective_fg_percentage].call(
        fgm: fgm,
        fga: fga,
        three_pm: three_pm
      )
    
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
      ratings_config_version = RatingsConfigVersion.current

      home_predictions = Prediction.joins(:game, :home_team_snapshot)
        .where(home_team_snapshot: { ratings_config_version: ratings_config_version, team_season: })
        .where(game: { start_time: ..@as_of })

      away_predictions = Prediction.joins(:game, :away_team_snapshot)
        .where(away_team_snapshot: { ratings_config_version: ratings_config_version, team_season: })
        .where(game: { start_time: ..@as_of })

      offensive_prediction_errors = home_predictions.pluck(:home_offensive_efficiency_error) + away_predictions.pluck(:away_offensive_efficiency_error)
      defensive_prediction_errors = home_predictions.pluck(:home_defensive_efficiency_error) + away_predictions.pluck(:away_defensive_efficiency_error)
      pace_prediction_errors = home_predictions.pluck(:pace_error) + away_predictions.pluck(:pace_error)

      {
        offensive_efficiency_volatility: StatisticsUtils.stddev(offensive_prediction_errors.compact),
        defensive_efficiency_volatility: StatisticsUtils.stddev(defensive_prediction_errors.compact),
        pace_volatility: StatisticsUtils.stddev(pace_prediction_errors.compact),
      }
    end
  end
end
