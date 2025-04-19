# frozen_string_literal: true

module ProphetRatings
  class TeamSeasonStatsAggregator
    AVERAGE_STATS = %i[
      turnover_rate
      offensive_rebound_rate
      free_throw_rate
      three_pt_attempt_rate
    ].freeze

    DERIVED_STATS = {
      effective_fg_percentage: ->(fgm:, fga:, three_pm:) {
        return nil if fga.zero?
        (fgm + 0.5 * three_pm) / fga.to_f
      }
    }.freeze

    def initialize(season)
      @season = season
    end

    def run
      off_stdevs = []
      def_stdevs = []
    
      TeamSeason.includes(:team_games).where(season: @season).find_each do |team_season|
        aggregates = calculate_average_stats(team_season)
        aggregates.merge!(calculate_efficiency_stddevs(team_season))
    
        off_stdevs << aggregates[:off_efficiency_std_deviation]
        def_stdevs << aggregates[:def_efficiency_std_deviation]
    
        team_season.update_columns(aggregates) if aggregates.any?
      end
    end

    private

    attr_reader :season

    def calculate_average_stats(team_season)
      aggregates = {}
    
      AVERAGE_STATS.each do |stat|
        values = team_season.team_games.map { |g| g.send(stat) }.compact
        avg = values.sum / values.size.to_f if values.any?
        aggregates[stat] = avg
      end
    
      fgm = team_season.team_games.sum(&:field_goals_made)
      fga = team_season.team_games.sum(&:field_goals_attempted)
      three_pm = team_season.team_games.sum(&:three_pt_made)
    
      aggregates[:effective_fg_percentage] = DERIVED_STATS[:effective_fg_percentage].call(
        fgm: fgm,
        fga: fga,
        three_pm: three_pm
      )
    
      aggregates
    end
    
    def calculate_efficiency_stddevs(team_season)
      off_vals = team_season.team_games.map(&:offensive_efficiency).compact
      def_vals = team_season.team_games.map(&:defensive_efficiency).compact
    
      {
        offensive_efficiency_std_dev: StatisticsUtils.stddev(off_vals),
        defensive_efficiency_std_dev: StatisticsUtils.stddev(def_vals)
      }
    end 
  end
end
