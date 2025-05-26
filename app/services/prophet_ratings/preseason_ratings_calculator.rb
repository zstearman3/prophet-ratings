# frozen_string_literal: true

module ProphetRatings
  class PreseasonRatingsCalculator
    def initialize(season = Season.current)
      @season = season
      @previous_season = Season.find_by(year: @season.year - 1)
    end

    def call
      @season.team_seasons.each do |team_season|
        preseason_ratings = calculate_preseason_ratings(team_season)

        team_season.update!(**preseason_ratings)
      end
    end

    private

    def calculate_preseason_ratings(team_season)
      {
        preseason_adj_offensive_efficiency: adj_off_efficiency(team_season),
        preseason_adj_defensive_efficiency: adj_def_efficiency(team_season),
        preseason_adj_pace: adj_pace(team_season)
      }
    end

    def adj_off_efficiency(team_season)
      blend_stat(team_season, :adj_offensive_efficiency) + (offseason_adjustment(team_season, :adj_off_efficiency) || 0.0)
    end

    def adj_def_efficiency(team_season)
      blend_stat(team_season, :adj_defensive_efficiency) + (offseason_adjustment(team_season, :adj_def_efficiency) || 0.0)
    end

    def adj_pace(team_season)
      blend_stat(team_season, :adj_pace) + (offseason_adjustment(team_season, :adj_pace) || 0.0)
    end

    def blend_stat(team_season, stat_key)
      mean_value = average_for_stat(stat_key)
      prev_team_season = @previous_season&.team_seasons&.find_by(team_id: team_season.team_id)
      previous_value = prev_team_season&.send(stat_key)

      return mean_value unless previous_value

      (0.15 * mean_value) + (0.85 * previous_value)
    end

    def average_for_stat(stat_key)
      case stat_key
      when :adj_offensive_efficiency, :adj_defensive_efficiency
        @previous_season&.average_efficiency || 105.5
      when :adj_pace
        @previous_season&.average_pace || 69.5
      end
    end

    def offseason_adjustment(team_season, stat_key)
      team_season.team_offseason_profile&.adjustment_for(stat_key) || 0
    end
  end
end
