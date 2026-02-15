# frozen_string_literal: true

module ProphetRatings
  class PreseasonInitializer
    def initialize(season)
      @season = season
    end

    def call
      ProphetRatings::PreseasonRatingsCalculator.new(@season).call

      @season.team_seasons.find_each do |team_season|
        team_season.update!(
          rating: team_season.preseason_adj_offensive_efficiency - team_season.preseason_adj_defensive_efficiency,
          adj_offensive_efficiency: team_season.preseason_adj_offensive_efficiency,
          adj_defensive_efficiency: team_season.preseason_adj_defensive_efficiency,
          adj_pace: team_season.preseason_adj_pace
        )
      end
    end
  end
end
