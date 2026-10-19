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
        BasketballCalculations::StatFormulae.three_point_proficiency(three_pm, three_pa, fga)
      }
    }.freeze

    def excluded_prediction_counts
      @options.fetch(:excluded_prediction_counts)
    end

    def initialize(season: Season.current, as_of: Time.current, ratings_config_version: nil, **options)
      @ratings_config_version = RatingsConfigVersion.resolve(ratings_config_version)
      @season = season
      @options = options.merge(as_of:, excluded_prediction_counts: Hash.new(0))
      @predictions_by_side = {}
    end

    ##
    # Aggregates and updates statistical metrics for all team seasons in the specified season up to the cutoff date.
    #
    # For each team season with finalized games before the cutoff, computes average stats, efficiency standard deviations, volatility metrics, home court advantages, and win/loss counts, then updates the corresponding record with the results.
    def run
      preload_predictions

      team_seasons = @season.rating_team_seasons.to_a
      ids = team_seasons.map(&:id)
      model_games = team_games_by_season_id(ids, results: Game.final)
      record_games = team_games_by_season_id(ids, results: Game.completed)

      team_seasons.each do |team_season|
        team_season.validate_model_inputs(@ratings_config_version)
        id = team_season.id
        team_games = model_games[id] || []

        aggregates = calculate_average_stats(team_games)
        aggregates.merge!(calculate_efficiency_stddevs(team_games))
        aggregates.merge!(calculate_volatility(team_season))
        aggregates.merge!(calculate_home_advantages(team_season))
        aggregates.merge!(calculate_wins_and_losses(record_games[id] || []))

        # rubocop:disable-next Rails/SkipsModelValidations
        team_season.update_columns(aggregates) if aggregates.any?
      end
    end

    private

    attr_reader :season

    def preload_predictions
      scope = @options[:verified_only] ? Prediction.selected_pregame : Prediction.selected_with_legacy
      predictions = scope
                    .where(ratings_config_version: @ratings_config_version)
                    .joins(:game)
                    .where(games: { season_id: season.id })
                    .merge(Game.final.through_schedule_date(@options.fetch(:as_of)))
                    .includes(:home_team_snapshot, :away_team_snapshot, game: %i[home_team_game away_team_game])
                    .to_a

      excluded_prediction_counts.clear
      predictions = predictions.reject do |prediction|
        reason = prediction.participant_exclusion_reason
        excluded_prediction_counts[reason] += 1 if reason
        reason
      end
      Rails.logger.info("Excluded prediction participants: #{excluded_prediction_counts}") if excluded_prediction_counts.any?

      predictions.each do |prediction|
        if @options[:verified_only]
          errors = GameFinalizer.prediction_error_attributes(prediction)
          raise ArgumentError, "Historical replay requires complete finalized team-game inputs for game=#{prediction.game_id}" unless errors

          prediction.assign_attributes(errors)
        end
        next if prediction.calculation_context.present?

        ModelConfiguration.validate_snapshots([prediction.home_team_snapshot, prediction.away_team_snapshot], @ratings_config_version)
      end

      @predictions_by_side[:home] = predictions
                                    .select { |p| p.forecast_team_season_id(0) }
                                    .group_by { |p| p.forecast_team_season_id(0) }

      @predictions_by_side[:away] = predictions
                                    .select { |p| p.forecast_team_season_id(1) }
                                    .group_by { |p| p.forecast_team_season_id(1) }
    end

    def team_games_by_season_id(team_season_ids, results:)
      return {} if team_season_ids.empty?

      TeamGame
        .joins(:game)
        .where(team_season_id: team_season_ids)
        .merge(results.through_schedule_date(@options.fetch(:as_of)))
        .includes(:game)
        .group_by(&:team_season_id)
    end

    public_class_method def self.sum_stat(team_games, stat)
      team_games.sum { |team_game| team_game.public_send(stat).to_i }
    end

    def calculate_average_stats(team_games)
      aggregates = {}

      AVERAGE_STATS.each do |stat|
        values = team_games.filter_map { |g| g.send(stat) }
        avg = values.sum / values.size.to_f if values.any?
        aggregates[stat] = avg
      end

      possession_vals = team_games.filter_map { |g| pace_for(g.game) }
      aggregates[:pace] = possession_vals.any? ? possession_vals.sum / possession_vals.size.to_f : nil

      fgm = self.class.sum_stat(team_games, :field_goals_made)
      fga = self.class.sum_stat(team_games, :field_goals_attempted)
      three_pm = self.class.sum_stat(team_games, :three_pt_made)
      three_pa = self.class.sum_stat(team_games, :three_pt_attempted)

      aggregates[:effective_fg_percentage] = DERIVED_STATS[:effective_fg_percentage].call(fgm:, fga:, three_pm:)
      aggregates[:three_pt_proficiency] = DERIVED_STATS[:three_pt_proficiency].call(fga:, three_pm:, three_pa:)

      aggregates
    end

    def calculate_efficiency_stddevs(team_games)
      off_vals = team_games.filter_map(&:offensive_efficiency)
      def_vals = team_games.filter_map(&:defensive_efficiency)

      {
        offensive_efficiency_std_dev: StatisticsUtils.stddev(off_vals),
        defensive_efficiency_std_dev: StatisticsUtils.stddev(def_vals)
      }
    end

    def pace_for(game)
      stat = @ratings_config_version.settings[:ratings_formula] == 'corrected_v1' ? :pace : :possessions
      game&.public_send(stat)
    end

    def offensive_efficiency_volatility(home_predictions, away_predictions)
      baseline = @ratings_config_version.settings.fetch(:baseline_volatility).fetch(:efficiency_volatility).to_f
      offensive_errors = (
        home_predictions.map(&:home_offensive_efficiency_error) +
        away_predictions.map(&:away_offensive_efficiency_error)
      ).compact

      blend_volatility(offensive_errors, baseline)
    end

    def defensive_efficiency_volatility(home_predictions, away_predictions)
      baseline = @ratings_config_version.settings.fetch(:baseline_volatility).fetch(:efficiency_volatility).to_f
      defensive_errors = (
        home_predictions.map(&:home_defensive_efficiency_error) +
        away_predictions.map(&:away_defensive_efficiency_error)
      ).compact

      blend_volatility(defensive_errors, baseline)
    end

    def pace_volatility(home_predictions, away_predictions)
      baseline = @ratings_config_version.settings.fetch(:baseline_volatility).fetch(:pace_volatility).to_f
      pace_errors = (home_predictions.map(&:pace_error) + away_predictions.map(&:pace_error)).compact

      blend_volatility(pace_errors, baseline)
    end

    def learning_weight(count, kind)
      rule = LearningSettings.for(@ratings_config_version.settings, kind)
      LearningSettings.weight(count, rule)
    end

    def blend_volatility(errors, baseline)
      weight = learning_weight(errors.size, :volatility)
      return baseline if weight.zero?

      (weight * StatisticsUtils.stddev(errors)) + ((1.0 - weight) * baseline)
    end

    def calculate_volatility(team_season)
      home_preds = @predictions_by_side.fetch(:home)[team_season.id] || []
      away_preds = @predictions_by_side.fetch(:away)[team_season.id] || []

      {
        offensive_efficiency_volatility: offensive_efficiency_volatility(home_preds, away_preds),
        defensive_efficiency_volatility: defensive_efficiency_volatility(home_preds, away_preds),
        pace_volatility: pace_volatility(home_preds, away_preds)
      }
    end

    ##
    # Calculates the home court offensive and defensive efficiency boosts for a team season.
    #
    # Computes average home advantage deltas from prediction errors.
    # Adjusts them relative to the baseline.
    # Blends with a baseline home court advantage value weighted by sample size.
    # Returns baseline values if there are no non-neutral home predictions.
    # @param team_season [TeamSeason] The team season for which to calculate home court advantages.
    # @return [Hash] A hash with :home_offense_boost (non-negative) and :home_defense_boost (non-positive), both rounded to three decimals.
    def calculate_home_advantages(team_season)
      baseline = @ratings_config_version.settings.fetch(:home_court_advantage).to_f
      home_preds = (@predictions_by_side.fetch(:home)[team_season.id] || []).select(&:forecast_home_venue?)
      return { home_offense_boost: baseline, home_defense_boost: -baseline } if home_preds.empty?

      off_deltas = home_preds.filter_map do |p|
        next if p.home_offensive_efficiency_error.nil?

        used_boost = p.forecast_home_boost(:home_offense_boost)
        p.home_offensive_efficiency_error - (used_boost - baseline)
      end

      def_deltas = home_preds.filter_map do |p|
        next if p.home_defensive_efficiency_error.nil?

        used_boost = p.forecast_home_boost(:home_defense_boost)
        p.home_defensive_efficiency_error - (used_boost + baseline)
      end

      avg_off = StatisticsUtils.average(off_deltas)
      avg_def = StatisticsUtils.average(def_deltas)
      off_weight = learning_weight(off_deltas.size, :home_court)
      def_weight = learning_weight(def_deltas.size, :home_court)

      blended_off = baseline - (off_weight * avg_off)
      blended_def = -baseline + ((@ratings_config_version.settings[:ratings_formula] == 'corrected_v1' ? -1 : 1) * def_weight * avg_def)

      {
        home_offense_boost: [blended_off, 0.0].max.round(3),
        home_defense_boost: [blended_def, 0.0].min.round(3)
      }
    end

    def calculate_wins_and_losses(team_games)
      conference_games = team_games.select { |tg| tg.game.final? && tg.game.in_conference? }

      wins, losses = team_games.partition do |tg|
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
