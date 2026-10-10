# frozen_string_literal: true

module ProphetRatings
  class PreseasonInitializer
    def initialize(season, ratings_config_version: nil)
      @ratings_config_version = RatingsConfigVersion.resolve(ratings_config_version)
      @config = @ratings_config_version.settings
      @season = season
    end

    def call
      @season.with_lock(requires_new: true) do
        validate_publication
        initialize_ratings
        publish
      end
    end

    # Used only by the explicitly scoped rebuild job; publication stays inside its window.
    def reset
      @season.with_lock { initialize_ratings }
    end

    def self.changed_ratings?(team_season)
      attributes = team_season.attributes
      %w[adj_offensive_efficiency adj_defensive_efficiency adj_pace].any? do |stat|
        value = attributes[stat]
        value.present? && value != attributes["preseason_#{stat}"]
      end
    end

    def self.prior_ratings(team_season)
      values = team_season.attributes.slice('preseason_adj_offensive_efficiency', 'preseason_adj_defensive_efficiency',
                                            'preseason_adj_pace')
                          .transform_keys do |key|
        key.delete_prefix('preseason_')
      end
      values.merge('rating' => values.values_at('adj_offensive_efficiency', 'adj_defensive_efficiency').reduce(:-))
    end

    private

    def validate_publication
      SeasonParticipationReview.new(@season).validate_publication(@ratings_config_version, @season.start_date - 1.day)
      return unless @season.current? || @season.games.final.exists? ||
                    @season.team_rating_snapshots.where.not(snapshot_date: @season.start_date - 1.day).exists? ||
                    @season.rating_team_seasons.any? { |team_season| self.class.changed_ratings?(team_season) }

      raise ArgumentError, 'Existing in-season outputs must be preserved; use an explicitly scoped season:rebuild_ratings.'
    end

    def publish
      @season.assign_attributes(publication_baselines)
      validate_prediction_baselines
      @season.save!
      OverallRatingsCalculator.new(@season, ratings_config_version: @ratings_config_version).publish(as_of: @season.start_date - 1.day)
    end

    def publication_baselines
      config = @config.fetch(:baseline_volatility)
      { average_efficiency: @season.rating_team_seasons.average(:adj_offensive_efficiency),
        average_pace: preseason_average_pace,
        efficiency_std_deviation: config.fetch(:efficiency_volatility), pace_std_deviation: config.fetch(:pace_volatility) }
    end

    def preseason_average_pace
      @season.rating_team_seasons.average(:adj_pace)
    end

    def validate_prediction_baselines
      return unless @season.predictions.exists? &&
                    @season.changed_attribute_names_to_save.intersect?(%w[average_efficiency average_pace])

      raise ArgumentError, 'Saved predictions depend on existing season baselines; ' \
                           'review them before changing preseason coverage or inputs.'
    end

    def reset_attributes(team_season)
      stats = OverallRatingsCalculator::ADJUSTED_STATS.values.flatten.map(&:to_s) & team_season.attribute_names
      stats.index_with(nil).merge(model_defaults)
    end

    def model_defaults
      home_boost = @config.fetch(:home_court_advantage)
      volatility = @config.dig(:baseline_volatility, :efficiency_volatility)
      {
        ratings_config_version: @ratings_config_version,
        home_offense_boost: home_boost,
        home_defense_boost: -home_boost,
        offensive_efficiency_volatility: volatility,
        defensive_efficiency_volatility: volatility,
        pace_volatility: @config.dig(:baseline_volatility, :pace_volatility)
      }
    end

    def initialize_ratings
      ProphetRatings::PreseasonRatingsCalculator.new(@season, ratings_config_version: @ratings_config_version).call

      @season.rating_team_seasons.find_each do |team_season|
        team_season.update!(reset_attributes(team_season).merge(self.class.prior_ratings(team_season)))
      end
    end
  end
end
