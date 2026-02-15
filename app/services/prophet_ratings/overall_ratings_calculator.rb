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

    def initialize(season = Season.current)
      @season = season
    end

    def call(as_of: [Time.current, Season.current.end_date].min)
      TeamSeasonStatsAggregator.new(season: @season, as_of:).run
      @season.update_average_ratings
      if (as_of.to_date - @season.start_date) > 14 && enough_finalized_data_for_adjustments?(as_of:)
        run_least_squares_adjustments(as_of:)
        recalculate_all_aggregate_ratings
      end
      TeamRatingSnapshotService.new(season: @season, as_of:).call
      @season.update_adjusted_averages
    end

    private

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def recalculate_all_aggregate_ratings
      team_seasons = TeamSeason.where(season: @season).to_a

      team_seasons.each do |ts|
        ts.rating = ts.adj_offensive_efficiency - ts.adj_defensive_efficiency
        ts.total_home_boost = ts.home_offense_boost - ts.home_defense_boost
        ts.total_volatility = (ts.offensive_efficiency_volatility + ts.defensive_efficiency_volatility) / 2.0
      end

      # Persist first round of updates
      TeamSeason.import team_seasons, on_duplicate_key_update: {
        columns: %i[rating total_home_boost total_volatility]
      }

      # Refresh records from DB with updated fields (optional but ensures accuracy)
      team_seasons = TeamSeason.where(season: @season).to_a

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
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    def run_least_squares_adjustments(as_of: nil)
      # Set default values for adj efficiency/pace before solving
      # rubocop:disable Rails/SkipsModelValidations
      TeamSeason.where(season: @season).update_all(
        adj_offensive_efficiency: @season.average_efficiency,
        adj_defensive_efficiency: @season.average_efficiency,
        adj_pace: @season.average_pace
      )
      # rubocop:enable Rails/SkipsModelValidations

      ADJUSTED_STATS.each do |raw_stat, (adj_stat, adj_stat_allowed)|
        ProphetRatings::AdjustedStatCalculator.new(
          season: @season,
          raw_stat:,
          adj_stat:,
          adj_stat_allowed:,
          as_of:
        ).call
      end
    end

    def assign_rank!(records, attr, rank_attr, direction = :desc)
      sorted = records.sort_by { |r| r.send(attr) }
      sorted.reverse! if direction == :desc
      sorted.each_with_index { |r, i| r.send(:"#{rank_attr}=", i + 1) }
    end

    def enough_finalized_data_for_adjustments?(as_of:)
      TeamGame
        .joins(:game, :team_season)
        .where(team_seasons: { season_id: @season.id })
        .where(games: { status: Game.statuses[:final], start_time: ..as_of })
        .group(:team_season_id)
        .having('COUNT(*) >= 2')
        .limit(2)
        .count
        .size >= 2
    end
  end
end
