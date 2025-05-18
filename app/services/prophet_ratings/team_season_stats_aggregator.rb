# frozen_string_literal: true

module ProphetRatings
  class TeamSeasonStatsAggregator
    AVERAGE_STATS = %i[
      turnover_rate offensive_rebound_rate free_throw_rate
      three_pt_attempt_rate offensive_efficiency defensive_efficiency
    ].freeze

    DERIVED_STATS = {
      effective_fg_percentage: lambda { |fgm:, fga:, three_pm:|
        return nil if fga.zero?

        (fgm + (0.5 * three_pm)) / fga.to_f
      },
      three_pt_proficiency: lambda { |fga:, three_pm:, three_pa:|
        nil if fga.zero?

        ((2 * (three_pm.to_f / three_pa)) + (three_pa.to_f / fga)) / 3.0
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
        aggregates.merge!(calculate_wins_and_losses(team_season))

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
        values = team_season.team_games.filter_map { |g| g.send(stat) }
        avg = values.sum / values.size.to_f if values.any?
        aggregates[stat] = avg
      end

      possession_vals = team_season.team_games.filter_map { |g| g.game&.possessions }
      aggregates[:pace] = possession_vals.sum / possession_vals.size.to_f if possession_vals.any?

      fgm = team_season.team_games.sum(&:field_goals_made)
      fga = team_season.team_games.sum(&:field_goals_attempted)
      three_pm = team_season.team_games.sum(&:three_pt_made)
      three_pa = team_season.team_games.sum(&:three_pt_attempted)

      aggregates[:effective_fg_percentage] = DERIVED_STATS[:effective_fg_percentage].call(fgm:, fga:, three_pm:)
      aggregates[:three_pt_proficiency] = DERIVED_STATS[:three_pt_proficiency].call(fga:, three_pm:, three_pa:)

      aggregates
    end

    def calculate_efficiency_stddevs(team_season)
      off_vals = team_season.team_games.filter_map(&:offensive_efficiency)
      def_vals = team_season.team_games.filter_map(&:defensive_efficiency)

      {
        offensive_efficiency_std_dev: StatisticsUtils.stddev(off_vals),
        defensive_efficiency_std_dev: StatisticsUtils.stddev(def_vals)
      }
    end

    def offensive_efficiency_volatility(home_predictions, away_predictions)
      baseline = Rails.application.config_for(:ratings).baseline_volatility[:efficiency_volatility].to_f
      offensive_errors = home_predictions.map(&:home_offensive_efficiency_error) + away_predictions.map(&:away_offensive_efficiency_error)

      return baseline if offensive_errors.size < 4

      calculated_volatility = StatisticsUtils.stddev(offensive_errors.compact)

      weight = [(offensive_errors.size / 16.0), 0.50].min.round(4)

      (weight * calculated_volatility) + ((1.0 - weight) * baseline)
    end

    def defensive_efficiency_volatility(home_predictions, away_predictions)
      baseline = Rails.application.config_for(:ratings).baseline_volatility[:efficiency_volatility].to_f
      defensive_errors = home_predictions.map(&:home_defensive_efficiency_error) + away_predictions.map(&:away_defensive_efficiency_error)

      return baseline if defensive_errors.size < 4

      calculated_volatility = StatisticsUtils.stddev(defensive_errors.compact)

      weight = [(defensive_errors.size / 16.0), 0.50].min.round(4)

      (weight * calculated_volatility) + ((1.0 - weight) * baseline)
    end

    def pace_volatility(home_predictions, away_predictions)
      baseline = Rails.application.config_for(:ratings).baseline_volatility[:pace_volatility].to_f
      pace_errors = home_predictions.map(&:pace_error) + away_predictions.map(&:pace_error)

      return baseline if pace_errors.size < 4

      calculated_volatility = StatisticsUtils.stddev(pace_errors.compact)

      weight = [(pace_errors.size / 16.0), 0.50].min.round(4)

      (weight * calculated_volatility) + ((1.0 - weight) * baseline)
    end

    def calculate_volatility(team_season)
      home_preds = home_preds_by_season[team_season.id] || []
      away_preds = away_preds_by_season[team_season.id] || []

      {
        offensive_efficiency_volatility: offensive_efficiency_volatility(home_preds, away_preds),
        defensive_efficiency_volatility: defensive_efficiency_volatility(home_preds, away_preds),
        pace_volatility: pace_volatility(home_preds, away_preds)
      }
    end

    def calculate_home_advantages(team_season)
      baseline = Rails.application.config_for(:ratings).home_court_advantage.to_f
      home_preds = (home_preds_by_season[team_season.id] || []).reject { |p| p.game.neutral? }
      return { home_offense_boost: baseline, home_defense_boost: -baseline } if home_preds.empty?

      off_deltas = home_preds.filter_map(&:home_offensive_efficiency_error)
      def_deltas = home_preds.filter_map(&:home_defensive_efficiency_error)

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

    def calculate_wins_and_losses(team_season)
      games = team_season.team_games
                         .includes(:game)
                         .where(game: { status: Game.statuses[:final], start_time: ..as_of })

      conference_games = games.select { |tg| tg.game.in_conference? }

      wins, losses = games.partition do |tg|
        game = tg.game
        if tg.home?
          game.home_team_score > game.away_team_score
        else
          game.away_team_score > game.home_team_score
        end
      end

      conference_wins, conference_losses = conference_games.partition do |tg|
        game = tg.game

        if tg.home?
          game.home_team_score > game.away_team_score
        else
          game.away_team_score > game.home_team_score
        end
      end

      { wins: wins.size,
        losses: losses.size,
        conference_wins: conference_wins.size,
        conference_losses: conference_losses.size }
    end
  end
end
