# frozen_string_literal: true

module ProphetRatings
  class GamePredictionBuilder
    ##
    # Initializes a new GamePredictionBuilder for the given game and ratings configuration version.
    # @param game The game for which predictions will be built.
    # @param ratings_config_version The ratings configuration version to use (defaults to the configured bundle).
    def initialize(game, ratings_config_version: nil)
      @game = game
      @ratings_config_version = RatingsConfigVersion.resolve(ratings_config_version)
      @generated_at = nil
      @config = @ratings_config_version.settings
    end

    ##
    # Builds and saves a game prediction based on the latest team rating snapshots and ratings configuration version.
    # Returns nil and logs a warning if required prediction inputs are unavailable.
    # @return [Prediction, nil] The saved prediction record, or nil if prediction could not be generated.
    def call
      game.with_lock do
        generate_revision
      end
    rescue ArgumentError => error
      Rails.logger.warn("Prediction skipped for game=#{game.id}: missing or invalid rating inputs: #{error.message}")
      nil
    end

    private

    attr_reader :game, :ratings_config_version

    def generate_revision
      @generated_at = Time.current
      build_revision if prediction_inputs_available?
    end

    def build_revision
      context = ForecastContext.capture(game, [home_snapshot, away_snapshot], ratings_config_version)
      result = ForecastContext.new(context).predictor.call
      save_revision(context, result)
    end

    def save_revision(context, result)
      previous = game.predictions.where(ratings_config_version:).where.not(revision_key: nil)
                     .order(generated_at: :desc, id: :desc).first
      return previous if identical_revision?(previous, context)

      game.predictions.create!(prediction_attributes(result).merge(provenance_attributes(context),
                                                                   ratings_config_version:, revision_key: revision_key(context, previous)))
    end

    def identical_revision?(previous, context)
      previous && retry_context(previous.calculation_context) == retry_context(context) && previous.forecast_kind == forecast_kind &&
        previous.input_cutoff == input_cutoff && previous.forecast_start_time == game.start_time
    end

    # Republishing identical sources can touch updated_at without changing any forecast input.
    def retry_context(context)
      context.as_json.deep_dup.tap do |inputs|
        inputs.fetch('season_source').delete('updated_at')
        inputs.fetch('snapshots').each { |snapshot| snapshot.fetch('source').delete('updated_at') }
      end
    end

    def revision_key(context, previous)
      identity = { context:, kind: forecast_kind, cutoff: input_cutoff, start_time: game.start_time, previous_id: previous&.id }
      Digest::SHA256.hexdigest(JSON.generate(identity))
    end

    def provenance_attributes(context)
      { home_team_snapshot: home_snapshot, away_team_snapshot: away_snapshot,
        calculation_context: context, forecast_kind:, generated_at: @generated_at,
        forecast_start_time: game.start_time, input_cutoff: }
    end

    def forecast_kind
      if game.scheduled? && game.start_time > @generated_at &&
         [game.home_team_score, game.away_team_score].compact.empty?
        'pregame'
      else
        'reconstruction'
      end
    end

    def input_cutoff
      [game.schedule_date - 1, Game.schedule_date_for(@generated_at)].min
    end

    def prediction_inputs_available?
      return true if home_snapshot && away_snapshot &&
                     required_snapshot_volatilities.all? { |value| value.is_a?(Numeric) && value.finite? && value >= 0 }

      Rails.logger.warn("Prediction skipped for game=#{game.id}: missing or invalid rating inputs (prior-day only); " \
                        'publish complete snapshots before the Eastern game date')
      false
    end

    # Shared-pace persisted diagnostics require snapshot SDs, not mutable fallbacks.
    def required_snapshot_volatilities
      return [] unless @config.dig(:prediction, :uncertainty_model) == 'shared_pace_v1'
      return [nil] unless home_snapshot && away_snapshot

      [home_snapshot, away_snapshot].flat_map do |snapshot|
        [snapshot.offensive_efficiency_volatility, snapshot.defensive_efficiency_volatility, snapshot.pace_volatility]
      end
    end

    def prediction_attributes(result)
      {
        home_offensive_efficiency: result[:meta][:home_expected_ortg],
        away_offensive_efficiency: result[:meta][:away_expected_ortg],
        home_defensive_efficiency: result[:meta][:away_expected_ortg],
        away_defensive_efficiency: result[:meta][:home_expected_ortg],
        home_score: result[:home_expected_score],
        away_score: result[:away_expected_score],
        home_win_probability: result[:win_probability_home],
        pace: result[:meta][:expected_pace]
      }
    end

    ##
    # Returns the latest rating snapshot for the game's home team season, or nil if none exists.
    def home_snapshot
      @home_snapshot ||= latest_snapshot(game.home_team_season)
    end

    ##
    # Returns the most recent rating snapshot for the away team's season, or nil if none exists.
    def away_snapshot
      @away_snapshot ||= latest_snapshot(game.away_team_season)
    end

    ##
    # Returns the most recent team rating snapshot for the given team season and ratings configuration version.
    # Excludes game-day data and sources that did not exist at generation.
    #
    # @param [TeamSeason] team_season - The team season for which to retrieve the snapshot.
    # @return [TeamRatingSnapshot, nil] The latest applicable rating snapshot, or nil if none exist.
    def latest_snapshot(team_season)
      TeamRatingSnapshot
        .where(team_season:, ratings_config_version:)
        .where(snapshot_date: ..input_cutoff)
        .where(created_at: ..@generated_at, updated_at: ..@generated_at)
        .order(snapshot_date: :desc)
        .first
    end
  end
end
