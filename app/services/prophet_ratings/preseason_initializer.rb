# frozen_string_literal: true

module ProphetRatings
  class PreseasonInitializer
    def initialize(season)
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
      return unless @season.current? || @season.games.final.exists? ||
                    @season.team_rating_snapshots.where.not(snapshot_date: @season.start_date - 1.day).exists? ||
                    @season.team_seasons.any? { |team_season| self.class.changed_ratings?(team_season) }

      raise ArgumentError, 'Existing in-season outputs must be preserved; use an explicitly scoped season:rebuild_ratings.'
    end

    def publish
      @season.assign_attributes(publication_baselines)
      validate_prediction_baselines
      @season.save!
      OverallRatingsCalculator.new(@season).publish(as_of: @season.start_date - 1.day)
    end

    def publication_baselines
      config = Rails.application.config_for(:ratings).deep_symbolize_keys.fetch(:baseline_volatility)
      { average_efficiency: @season.team_seasons.average(:adj_offensive_efficiency),
        average_pace: preseason_average_pace,
        efficiency_std_deviation: config.fetch(:efficiency_volatility), pace_std_deviation: config.fetch(:pace_volatility) }
    end

    def preseason_average_pace
      @season.team_seasons.average(:adj_pace)
    end

    def validate_prediction_baselines
      return unless @season.predictions.exists? &&
                    @season.changed_attribute_names_to_save.intersect?(%w[average_efficiency average_pace])

      raise ArgumentError, 'Saved predictions depend on existing season baselines; ' \
                           'review them before changing preseason coverage or inputs.'
    end

    def initialize_ratings
      ProphetRatings::PreseasonRatingsCalculator.new(@season).call

      @season.team_seasons.find_each do |team_season|
        team_season.update!(self.class.prior_ratings(team_season))
      end
    end
  end
end
