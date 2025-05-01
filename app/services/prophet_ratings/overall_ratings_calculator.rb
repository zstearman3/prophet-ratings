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
      three_pt_attempt_rate: %i[adj_three_pt_attempt_rate adj_three_pt_attempt_rate_allowed]
    }.freeze

    def initialize(season = Season.current)
      @season = season
    end

    def calculate_season_ratings(as_of: Time.current)
      TeamSeasonStatsAggregator.new(season: @season, as_of:).run
      @season.update_average_ratings

      run_least_squares_adjustments(as_of:) if (as_of.to_date - @season.start_date) > 14

      TeamSeason.where(season: @season).find_each do |ts|
        ts.update!(rating: calculate_rating(ts))
      end

      TeamRatingSnapshotService.new(season: @season, as_of:).call
    end

    private

    def calculate_rating(ts)
      ts.adj_offensive_efficiency - ts.adj_defensive_efficiency
    end

    def run_least_squares_adjustments(as_of: nil)
      # Set default values for adj efficiency/pace before solving
      TeamSeason.where(season: @season).update_all(
        adj_offensive_efficiency: @season.average_efficiency,
        adj_defensive_efficiency: @season.average_efficiency,
        adj_pace: @season.average_pace
      )

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
  end
end
