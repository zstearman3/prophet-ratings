# frozen_string_literal: true

module ProphetRatings
  DEFAULTS = Rails.application.config_for(:defaults).deep_symbolize_keys unless const_defined?(:DEFAULTS)

  class GameSimulator
    ##
    # Initializes a new game simulator with team rating snapshots, upset modifier, neutral site flag, and season context.
    # @param home_rating_snapshot The rating snapshot for the home team.
    # @param away_rating_snapshot The rating snapshot for the away team.
    # @param upset_modifier [Float] A multiplier affecting the likelihood of upsets (default: 1.0).
    # @param neutral [Boolean] Whether the game is played at a neutral site (default: false).
    # @param season The season context for the simulation (default: current season).
    def initialize(home_rating_snapshot:, away_rating_snapshot:, upset_modifier: 1.0, neutral: false, season: Season.current)
      @home_rating_snapshot = home_rating_snapshot
      @away_rating_snapshot = away_rating_snapshot
      @upset_modifier = upset_modifier
      @neutral = neutral
      @season = season
    end

    ##
    # Simulates a basketball game between two teams using their rating snapshots and season data.
    # @return [Hash] A hash containing the home and away team names and their simulated scores.
    # @raise [ArgumentError] If either the home or away rating snapshot is missing.
    def call
      raise ArgumentError, 'Missing home or away rating snapshot' unless @home_rating_snapshot && @away_rating_snapshot

      pace = simulate_pace
      home_ortg = simulate_home_ortg
      away_ortg = simulate_away_ortg
      {
        home_team: home_rating_snapshot.team.school,
        away_team: away_rating_snapshot.team.school,
        home_score: (pace * (home_ortg / 100.0)).round(2),
        away_score: (pace * (away_ortg / 100.0)).round(2)
      }
    end

    private

    attr_reader :home_rating_snapshot, :away_rating_snapshot, :season

    ##
    # Simulates the game's pace using a Gaussian distribution based on expected pace and total pace volatility.
    # @return [Float] The simulated pace value.
    def simulate_pace
      Gaussian.new(expected_pace, total_pace_volatility).rand
    end

    ##
    # Simulates the home team's offensive rating for the game using a Gaussian distribution based on expected value and volatility.
    # @return [Float] The simulated home offensive rating.
    def simulate_home_ortg
      Gaussian.new(home_expected_ortg, total_home_volatility).rand
    end

    ##
    # Simulates the away team's offensive rating for the game using a Gaussian distribution based on expected value and volatility.
    # @return [Float] The simulated away offensive rating.
    def simulate_away_ortg
      Gaussian.new(away_expected_ortg, total_away_volatility).rand
    end

    ##
    # Calculates the expected pace for the simulated game based on both teams' adjusted paces and the season average.
    # @return [Float] The expected number of possessions for the game.
    def expected_pace
      @expected_pace ||= (home_rating_snapshot.adj_pace - season.average_pace) +
                         (away_rating_snapshot.adj_pace - season.average_pace) +
                         season.average_pace
    end

    ##
    # Calculates the expected offensive rating for the home team based on team and season efficiencies and a home offense boost.
    # @return [Float, nil] The expected home offensive rating, or nil if rating snapshots are missing.
    def home_expected_ortg
      return unless home_rating_snapshot && away_rating_snapshot

      @home_expected_ortg ||=
        home_rating_snapshot.adj_offensive_efficiency +
        away_rating_snapshot.adj_defensive_efficiency -
        season_average_efficiency +
        home_offense_boost
    end

    ##
    # Calculates the expected offensive rating for the away team based on team rating snapshots and season averages.
    # @return [Float, nil] The expected away offensive rating, or nil if required rating snapshots are missing.
    def away_expected_ortg
      return unless home_rating_snapshot && away_rating_snapshot

      @away_expected_ortg ||=
        away_rating_snapshot.adj_offensive_efficiency +
        home_rating_snapshot.adj_defensive_efficiency -
        season_average_efficiency +
        home_defense_boost
    end

    def home_offense_boost
      return 0 if @neutral

      home_rating_snapshot&.home_offense_boost || default_home_boost
    end

    def home_defense_boost
      return 0 if @neutral

      home_rating_snapshot&.home_defense_boost || -default_home_boost
    end

    ##
    # Retrieves the default home court advantage value from the ratings configuration.
    # @return [Numeric] The configured home court advantage value.
    def default_home_boost
      @default_home_boost ||= Rails.application.config_for(:ratings).home_court_advantage
    end

    ##
    # Returns the season's average efficiency, falling back to a default value if unavailable.
    # @return [Float] The average efficiency for the season.
    def season_average_efficiency
      season.average_efficiency || default_season_average_efficiency
    end

    def default_season_average_efficiency
      @default_season_average_efficiency ||= DEFAULTS[:season_defaults][:average_efficiency]
    end

    ##
    # Returns the total volatility for the home team's offensive rating as calculated by the volatility calculator.
    # @return [Float] The total home offensive volatility value.
    def total_home_volatility
      volatility_calculator.total_home_volatility
    end

    ##
    # Returns the total volatility for the away team's offensive rating as calculated by the volatility calculator.
    # @return [Float] The total away offensive volatility value.
    def total_away_volatility
      volatility_calculator.total_away_volatility
    end

    ##
    # Returns the total volatility for game pace as calculated by the volatility calculator.
    # @return [Float] The standard deviation used for simulating game pace.
    def total_pace_volatility
      volatility_calculator.total_pace_volatility
    end

    ##
    # Lazily initializes and returns a VolatilityCalculator for the current simulation parameters.
    # @return [ProphetRatings::VolatilityCalculator] The volatility calculator instance used for this simulation.
    def volatility_calculator
      @volatility_calculator ||= ProphetRatings::VolatilityCalculator.new(
        home_rating_snapshot: home_rating_snapshot,
        away_rating_snapshot: away_rating_snapshot,
        season: season,
        upset_modifier: @upset_modifier,
        neutral: @neutral
      )
    end
  end
end
