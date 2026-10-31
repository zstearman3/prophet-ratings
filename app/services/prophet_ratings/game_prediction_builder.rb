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
      @generation = { at: nil }
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

    # Historical working inputs are explicit reconstructions, never operational issuances.
    def reconstruct(snapshots:)
      game.with_lock do
        @generation[:home] = snapshots[0]
        @generation[:away] = snapshots[1]
        @generation[:at] = Time.current
        build_revision
      end
    end

    private

    attr_reader :game, :ratings_config_version

    def generate_revision
      @generation[:at] = Time.current
      build_revision if prediction_inputs_available?
    end

    def build_revision
      context = ForecastContext.capture(game, [snapshot(:home), snapshot(:away)], ratings_config_version)
      result = ForecastContext.new(context).predictor.call
      save_revision(context, result)
    end

    def save_revision(context, result)
      predictions = game.predictions
      previous = predictions.where(ratings_config_version:).where.not(revision_key: nil)
                            .order(generated_at: :desc, id: :desc).first
      return previous if identical_revision?(previous, context)

      attributes = self.class.prediction_attributes(result).merge(provenance_attributes(context))
      predictions.create!(attributes.merge(ratings_config_version:, revision_key: revision_key(context, previous)))
    end

    def identical_revision?(previous, context)
      previous &&
        GamePredictionBuilder.retry_context(previous.calculation_context) == GamePredictionBuilder.retry_context(context) &&
        previous.attributes.values_at('forecast_kind', 'input_cutoff',
                                      'forecast_start_time') == [forecast_kind, input_cutoff, game.start_time]
    end

    # Republishing identical sources can touch updated_at without changing any forecast input.
    public_class_method def self.retry_context(context)
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
      home = snapshot(:home)
      away = snapshot(:away)
      { home_team_snapshot: home.persisted? ? home : nil,
        away_team_snapshot: away.persisted? ? away : nil,
        calculation_context: context, forecast_kind:, generated_at: @generation[:at],
        forecast_start_time: game.start_time, input_cutoff: }
    end

    def forecast_kind
      return 'reconstruction' unless snapshot(:home).persisted? && snapshot(:away).persisted?

      if game.scheduled? && game.start_time > @generation[:at] &&
         [game.home_team_score, game.away_team_score].compact.empty?
        'pregame'
      else
        'reconstruction'
      end
    end

    def input_cutoff
      # Preseason publications can be dated just before opening day even when published earlier.
      publication_cutoff = [Game.schedule_date_for(@generation[:at]), game.season.start_date - 1].max
      [game.schedule_date - 1, publication_cutoff].min
    end

    def prediction_inputs_available?
      return true if snapshot(:home) && snapshot(:away) &&
                     required_snapshot_volatilities.all? { |value| value.is_a?(Numeric) && value.finite? && value >= 0 }

      Rails.logger.warn("Prediction skipped for game=#{game.id}: missing or invalid rating inputs (snapshot cutoff); " \
                        'publish complete snapshots before the Eastern game date')
      false
    end

    # Shared-pace persisted diagnostics require snapshot SDs, not mutable fallbacks.
    def required_snapshot_volatilities
      return [] unless @config.dig(:prediction, :uncertainty_model) == 'shared_pace_v1'

      snapshots = [snapshot(:home), snapshot(:away)]
      return [nil] unless snapshots.all?

      snapshots.flat_map do |snapshot|
        [snapshot.offensive_efficiency_volatility, snapshot.defensive_efficiency_volatility, snapshot.pace_volatility]
      end
    end

    public_class_method def self.prediction_attributes(result)
      meta = result[:meta]
      home_efficiency, away_efficiency = meta.values_at(:home_expected_ortg, :away_expected_ortg)
      {
        home_offensive_efficiency: home_efficiency,
        away_offensive_efficiency: away_efficiency,
        home_defensive_efficiency: away_efficiency,
        away_defensive_efficiency: home_efficiency,
        home_score: result[:home_expected_score],
        away_score: result[:away_expected_score],
        home_win_probability: result[:win_probability_home],
        pace: meta[:expected_pace]
      }
    end

    def snapshot(side)
      @generation[side] ||= latest_snapshot(game.public_send("#{side}_team_season"))
    end

    ##
    # Returns the most recent team rating snapshot for the given team season and ratings configuration version.
    # Excludes game-day data and sources that did not exist at generation; preseason dates may be ahead of issuance.
    #
    # @param [TeamSeason] team_season - The team season for which to retrieve the snapshot.
    # @return [TeamRatingSnapshot, nil] The latest applicable rating snapshot, or nil if none exist.
    def latest_snapshot(team_season)
      generated_at = @generation[:at]
      TeamRatingSnapshot
        .where(team_season:, ratings_config_version:)
        .where(snapshot_date: ..input_cutoff)
        .where(created_at: ..generated_at, updated_at: ..generated_at)
        .order(snapshot_date: :desc)
        .first
    end
  end
end
