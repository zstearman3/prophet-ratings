# frozen_string_literal: true

module ProphetRatings
  class PreseasonRatingsCalculator
    PRESEASON_CONFIG = Rails.application.config_for(:ratings).deep_symbolize_keys.fetch(:preseason)
    PREVIOUS_SEASON_WEIGHT = PRESEASON_CONFIG.fetch(:previous_season_weight)

    def initialize(season = Season.current)
      @season = season
      @previous_season = Season.find_by(year: @season.year - 1)
    end

    def call
      @season.team_seasons.includes(:team_offseason_profile).find_each do |team_season|
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

      ((1 - PREVIOUS_SEASON_WEIGHT) * mean_value) + (PREVIOUS_SEASON_WEIGHT * previous_value)
    end

    def average_for_stat(stat_key)
      efficiency_baseline = PRESEASON_CONFIG.fetch(:fallback_efficiency)
      case stat_key
      when :adj_offensive_efficiency
        @previous_season&.avg_adj_offensive_efficiency ||
          @previous_season&.average_efficiency || efficiency_baseline
      when :adj_defensive_efficiency
        @previous_season&.avg_adj_defensive_efficiency ||
          @previous_season&.average_efficiency || efficiency_baseline
      when :adj_pace
        @previous_season&.average_pace || PRESEASON_CONFIG.fetch(:fallback_pace)
      end
    end

    def offseason_adjustment(team_season, stat_key)
      team_season.team_offseason_profile&.adjustment_for(stat_key) || 0
    end
  end
end
