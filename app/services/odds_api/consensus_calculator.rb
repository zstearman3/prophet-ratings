# frozen_string_literal: true

module OddsApi
  class ConsensusCalculator
    def initialize(bookmakers:, home_team:, away_team:)
      @bookmakers = Array(bookmakers)
      @home_names = team_identifiers(home_team)
      @away_names = team_identifiers(away_team)
    end

    def consensus
      {
        fetched_at: Time.current,
        moneyline_home: average_moneyline(@home_names),
        moneyline_away: average_moneyline(@away_names),
        spread_point: consensus_spread_point,
        spread_home_odds: average_spread_odds(@home_names),
        spread_away_odds: average_spread_odds(@away_names),
        total_points: consensus_total_point,
        total_over_odds: average_total_odds('Over'),
        total_under_odds: average_total_odds('Under')
      }
    end

    private

    ##
    # Calculates the average moneyline odds for the specified team across all bookmakers.
    # @param [String] team_name - The name of the team for which to calculate the average moneyline.
    # @return [Float, nil] The average moneyline odds, or nil if no prices are available.
    def average_moneyline(team_names)
      prices = extract_prices('h2h', team_names)
      average(prices)
    end

    ##
    # Calculates the average spread odds for the specified team across all bookmakers.
    # @param [String] team_name - The name of the team for which to calculate average spread odds.
    # @return [Float, nil] The average spread odds, or nil if no data is available.
    def average_spread_odds(team_names)
      entries = extract_market('spreads').select { |outcome| team_names.include?(value_for(outcome, :name)) }
      average(entries.filter_map { |outcome| value_for(outcome, :price) })
    end

    ##
    # Returns the most common spread point value across all bookmakers.
    # @return [Numeric, nil] The mode of spread points, or nil if no spread points are available.
    def consensus_spread_point
      points = extract_market('spreads').filter_map { |outcome| value_for(outcome, :point) }
      mode(points)
    end

    ##
    # Calculates the average odds for total bets (e.g., "Over" or "Under") with the specified name across all bookmakers.
    # @param [String] name - The name of the total bet outcome ("Over" or "Under").
    # @return [Float, nil] The average odds for the specified total bet, or nil if no odds are available.
    def average_total_odds(name)
      entries = extract_market('totals').select { |outcome| value_for(outcome, :name) == name }
      average(entries.filter_map { |outcome| value_for(outcome, :price) })
    end

    ##
    # Returns the most common total points line across all bookmakers.
    # @return [Numeric, nil] The mode of total points, or nil if unavailable.
    def consensus_total_point
      points = extract_market('totals').filter_map { |outcome| value_for(outcome, :point) }
      mode(points)
    end

    ##
    # Retrieves an array of prices for a given team from the specified market across all bookmakers.
    # @param [String] market_key The key identifying the market type (e.g., 'spreads', 'h2h').
    # @param [String] team_name The name of the team whose prices are to be extracted.
    # @return [Array<Numeric>] An array of price values for the specified team; empty if none found.
    def extract_prices(market_key, team_names)
      extract_market(market_key)
        .select { |outcome| team_names.include?(value_for(outcome, :name)) }
        .filter_map { |outcome| value_for(outcome, :price) }
    end

    ##
    # Extracts all outcome entries for a given market key from each bookmaker.
    # @param [String] market_key - The key identifying the market to extract (e.g., 'spreads', 'totals').
    # @return [Array<Hash>] An array of outcome hashes from all matching markets across bookmakers.
    # Returns an empty array if no outcomes are found.
    def extract_market(market_key)
      @bookmakers.flat_map do |book|
        markets = Array(value_for(book, :markets))
        market = markets.find { |entry| value_for(entry, :key) == market_key }
        market ? Array(value_for(market, :outcomes)) : []
      end
    end

    def team_identifiers(team)
      candidates = []
      candidates << team.school if team.respond_to?(:school)
      candidates << team.the_odds_api_team_id if team.respond_to?(:the_odds_api_team_id)

      if team.respond_to?(:team_aliases)
        candidates.concat(Array(team.team_aliases).map { |team_alias| team_alias.value })
      end

      candidates.compact.map(&:to_s).uniq
    end

    def value_for(hash, key)
      hash[key] || hash[key.to_s]
    end

    def average(values)
      return nil if values.empty?

      (values.sum.to_f / values.size).round(2)
    end

    def mode(array)
      return nil if array.empty?

      array.group_by(&:itself).max_by { |_, v| v.size }[0]
    end
  end
end
