# frozen_string_literal: true

module ProphetRatings
  class OverallRatingsCalculator
    ADJUSTED_STATS = {
      offensive_efficiency: %i[adj_offensive_efficiency adj_defensive_efficiency],
      possessions: %i[adj_pace adj_pace_allowed],
      effective_fg_percentage: %i[adj_effective_fg_percentage adj_effective_fg_percentage_allowed],
      turnover_rate: %i[adj_turnover_rate adj_turnover_rate_forced],
      offensive_rebound_rate: %i[adj_offensive_rebound_rate adj_defensive_rebound_rate],
      free_throw_rate: %i[adj_free_throw_rate adj_free_throw_rate_allowed],
      three_pt_proficiency: %i[adj_three_pt_proficiency adj_three_pt_proficiency_allowed]
    }.freeze

    def initialize(season = Season.current, ratings_config_version: nil)
      @ratings_config_version = RatingsConfigVersion.resolve(ratings_config_version)
      @config = @ratings_config_version.settings
      @season = season
      validate_target_season!
    end

    def call(as_of: nil)
      as_of = self.class.cutoff_date(as_of, @season)
      @season.with_lock(requires_new: true) { calculate(as_of:) }
    end

    def calculate(as_of:)
      validate_live_versions!(as_of)
      TeamSeasonStatsAggregator.new(season: @season, as_of:, ratings_config_version: @ratings_config_version).run
      @season.update_average_ratings
      run_least_squares_adjustments(as_of:) if adjustment_period?(as_of) && enough_finalized_data_for_adjustments?(as_of:)
      publish(as_of:)
    end

    def publish(as_of:)
      @season.with_lock(requires_new: true) { publish_ratings(as_of:) }
    end

    def publish_ratings(as_of:)
      validate_live_versions!(as_of)
      update_live_ratings
      @season.rating_team_seasons.find_each { |team_season| team_season.update!(ratings_config_version: @ratings_config_version) }
      TeamRatingSnapshotService.new(season: @season, as_of:, ratings_config_version: @ratings_config_version).call
    end

    private :calculate, :publish_ratings

    def self.missing_ratings(team_season, config)
      attributes = team_season.attributes
      config = config.fetch(:preseason)
      { 'adj_offensive_efficiency' => :fallback_efficiency, 'adj_defensive_efficiency' => :fallback_efficiency,
        'adj_pace' => :fallback_pace }.to_h do |stat, fallback|
        [stat, attributes[stat] || attributes["preseason_#{stat}"] || config.fetch(fallback)]
      end
    end

    def self.sorted_ratings(records, attr, multiplier)
      records.index_with { |record| record.public_send(attr) }.compact_blank.sort_by do |record, value|
        [multiplier * value, record.team_id]
      end.map(&:first)
    end

    def self.clear_excluded_ranks(season)
      return if season.participation_review.blank?

      ranks = (TeamRatingSnapshot::STORED_RANKS + ['pace_rank']).index_with(nil)
      season.team_seasons.where.not(id: season.rating_team_seasons.select(:id)).find_each { |row| row.update!(ranks) }
    end

    private

    def adjustment_period?(as_of)
      (as_of.to_date - @season.start_date) > @config.dig(:preseason, :adjustment_start_after_days)
    end

    def update_live_ratings
      self.class.clear_excluded_ranks(@season)
      fill_missing_ratings
      fill_prediction_baselines
      recalculate_all_aggregate_ratings
      @season.update_adjusted_averages
    end

    def validate_live_versions!(as_of)
      SeasonParticipationReview.new(@season).validate_publication(@ratings_config_version, as_of)
      @season.rating_team_seasons.find_each { |team_season| team_season.validate_model_inputs(@ratings_config_version) }
    end

    def validate_target_season!
      raise ArgumentError, 'A persisted target season is required' unless @season.is_a?(Season) && @season.persisted?

      start_date = @season.start_date
      end_date = @season.end_date
      return if start_date && end_date && start_date < end_date

      raise ArgumentError, 'A persisted target season with valid start/end dates is required'
    end

    public_class_method def self.cutoff_date(value, season)
      date = case value
             when NilClass then Game.current_schedule_date
             when String then date_only_cutoff(value)
             when Date, Time, ActiveSupport::TimeWithZone then Game.schedule_day_range(value).begin.to_date
             else raise ArgumentError, 'Cutoff must be a date, time, or ISO date string'
             end
      [date, season.end_date].min
    end

    public_class_method def self.date_only_cutoff(value)
      date = Date.iso8601(value)
      raise ArgumentError, 'String cutoffs must be YYYY-MM-DD; pass timestamps as time objects' unless date.iso8601 == value

      date
    end

    def fill_prediction_baselines
      config = @config
      @season.update!(
        average_efficiency: @season.average_efficiency || @season.rating_team_seasons.average(:preseason_adj_offensive_efficiency) ||
                            config.dig(:preseason, :fallback_efficiency),
        efficiency_std_deviation: @season.efficiency_std_deviation || config.dig(:baseline_volatility, :efficiency_volatility),
        pace_std_deviation: @season.pace_std_deviation || config.dig(:baseline_volatility, :pace_volatility)
      )
    end

    def fill_missing_ratings
      @season.rating_team_seasons.find_each { |team_season| team_season.update!(self.class.missing_ratings(team_season, @config)) }
    end

    # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
    def recalculate_all_aggregate_ratings
      team_seasons = @season.rating_team_seasons.to_a
      ratings_config = @config
      default_home_boost = ratings_config[:home_court_advantage].to_f
      default_efficiency_volatility = ratings_config.dig(:baseline_volatility, :efficiency_volatility).to_f

      team_seasons.each do |ts|
        home_offense_boost = ts.home_offense_boost || default_home_boost
        home_defense_boost = ts.home_defense_boost || -default_home_boost
        offensive_volatility = ts.offensive_efficiency_volatility || default_efficiency_volatility
        defensive_volatility = ts.defensive_efficiency_volatility || default_efficiency_volatility

        ts.home_offense_boost = home_offense_boost
        ts.home_defense_boost = home_defense_boost
        ts.offensive_efficiency_volatility = offensive_volatility
        ts.defensive_efficiency_volatility = defensive_volatility
        ts.pace_volatility ||= ratings_config.dig(:baseline_volatility, :pace_volatility).to_f
        ts.rating = ts.adj_offensive_efficiency - ts.adj_defensive_efficiency
        ts.total_home_boost = home_offense_boost - home_defense_boost
        ts.total_volatility = (offensive_volatility + defensive_volatility) / 2.0
      end

      # Persist first round of updates
      TeamSeason.import team_seasons, on_duplicate_key_update: {
        columns: %i[
          home_offense_boost
          home_defense_boost
          offensive_efficiency_volatility
          defensive_efficiency_volatility
          rating
          total_home_boost
          total_volatility
          pace_volatility
        ]
      }

      # Refresh records from DB with updated fields (optional but ensures accuracy)
      team_seasons = @season.rating_team_seasons.to_a

      # Compute ranks
      assign_rank!(team_seasons, :rating, :overall_rank, :desc)
      assign_rank!(team_seasons, :adj_offensive_efficiency, :adj_offensive_efficiency_rank, :desc)
      assign_rank!(team_seasons, :adj_defensive_efficiency, :adj_defensive_efficiency_rank, :asc)
      assign_rank!(team_seasons, :adj_pace, :pace_rank, :desc)
      assign_rank!(team_seasons, :adj_free_throw_rate, :adj_free_throw_rate_rank, :desc)
      assign_rank!(team_seasons, :adj_free_throw_rate_allowed, :adj_free_throw_rate_allowed_rank, :asc)
      assign_rank!(team_seasons, :adj_turnover_rate, :adj_turnover_rate_rank, :asc)
      assign_rank!(team_seasons, :adj_turnover_rate_forced, :adj_turnover_rate_forced_rank, :desc)
      assign_rank!(team_seasons, :adj_offensive_rebound_rate, :adj_offensive_rebound_rate_rank, :desc)
      assign_rank!(team_seasons, :adj_defensive_rebound_rate, :adj_defensive_rebound_rate_rank, :desc)
      assign_rank!(team_seasons, :adj_effective_fg_percentage, :adj_effective_fg_percentage_rank, :desc)
      assign_rank!(team_seasons, :adj_effective_fg_percentage_allowed, :adj_effective_fg_percentage_allowed_rank, :asc)
      assign_rank!(team_seasons, :adj_three_pt_proficiency, :adj_three_pt_proficiency_rank, :desc)
      assign_rank!(team_seasons, :adj_three_pt_proficiency_allowed, :adj_three_pt_proficiency_allowed_rank, :asc)
      assign_rank!(team_seasons, :adj_pace, :adj_pace_rank, :desc)

      # Persist ranks
      TeamSeason.import team_seasons, on_duplicate_key_update: {
        columns: %i[
          overall_rank
          adj_offensive_efficiency_rank
          adj_defensive_efficiency_rank
          pace_rank
          adj_free_throw_rate_rank
          adj_free_throw_rate_allowed_rank
          adj_turnover_rate_rank
          adj_turnover_rate_forced_rank
          adj_offensive_rebound_rate_rank
          adj_defensive_rebound_rate_rank
          adj_effective_fg_percentage_rank
          adj_effective_fg_percentage_allowed_rank
          adj_three_pt_proficiency_rank
          adj_three_pt_proficiency_allowed_rank
          adj_pace_rank
        ]
      }
    end

    def run_least_squares_adjustments(as_of: nil)
      ADJUSTED_STATS.each do |raw_stat, (adj_stat, adj_stat_allowed)|
        ProphetRatings::AdjustedStatCalculator.new(
          season: @season,
          raw_stat:,
          adj_stat:,
          adj_stat_allowed:,
          as_of:,
          ratings_config_version: @ratings_config_version
        ).call
      end
    end

    def assign_rank!(records, attr, rank_attr, direction = :desc)
      ranks = self.class.sorted_ratings(records, attr, direction == :desc ? -1 : 1)
                  .each_with_index.to_h { |record, index| [record, index + 1] }
      records.each { |record| record.public_send(:"#{rank_attr}=", ranks[record]) }
    end

    def enough_finalized_data_for_adjustments?(as_of:)
      TeamGame
        .joins(:game, :team_season)
        .where(team_season_id: @season.rating_team_seasons.select(:id))
        .merge(Game.final.through_schedule_date(as_of))
        .group(:team_season_id)
        .having('COUNT(*) >= 2')
        .limit(2)
        .count
        .size >= 2
    end
  end
end
