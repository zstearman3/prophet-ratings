# frozen_string_literal: true

module ProphetRatings
  class OverallRatingsCalculator

    ADJUSTED_STATS = {
      offensive_rating: [:adj_offensive_efficiency, :adj_defensive_efficiency],
      effective_fg_percentage: [:adj_effective_fg_percentage, :adj_effective_fg_percentage_allowed],
      turnover_rate: [:adj_turnover_rate, :adj_turnover_rate_forced],
      offensive_rebound_rate: [:adj_offensive_rebound_rate, :adj_defensive_rebound_rate],
      free_throw_rate: [:adj_free_throw_rate, :adj_free_throw_rate_allowed],
      three_point_attempt_rate: [:adj_three_point_attempt_rate, :adj_three_point_attempt_rate_allowed]
    }.freeze

    def initialize(season)
      @season = season
      @acceptble_error = 100.0
    end

    def calculate_season_ratings
      @season.update_average_ratings

      # Set default values for adj efficiency/pace before solving
      TeamSeason.where(season: @season).update_all(
        adj_offensive_efficiency: @season.average_efficiency,
        adj_defensive_efficiency: @season.average_efficiency,
        adj_pace: @season.average_pace
      )
    
      run_least_squares_adjustments
    
      TeamSeason.where(season: @season).find_each do |s|
        s.update!(rating: s.adj_offensive_efficiency - s.adj_defensive_efficiency)
      end
    end

    private

    def run_least_squares_adjustments
      ADJUSTED_STATS.each do |raw_stat, (adj_stat, adj_stat_allowed)|
        ProphetRatings::LeastSquaresAdjustedStatCalculator.new(
          season: @season,
          raw_stat:,
          adj_stat:,
          adj_stat_allowed:
        ).run
      end
    end
  end
end
