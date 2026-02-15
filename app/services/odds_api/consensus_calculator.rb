# frozen_string_literal: true

module OddsApi
  class ConsensusCalculator
    def initialize(bookmakers:, home_team:, away_team:)
      @bookmakers = bookmakers
      @home_name = home_team.the_odds_api_team_id
      @away_name = away_team.the_odds_api_team_id
    end

    def consensus
      {
        fetched_at: Time.current,
        moneyline_home: average_moneyline(@home_name),
        moneyline_away: average_moneyline(@away_name),
        spread_point: consensus_spread_point,
        spread_home_odds: average_spread_odds(@home_name),
        spread_away_odds: average_spread_odds(@away_name),
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
    def average_moneyline(team_name)
      prices = extract_prices('h2h', team_name)
      average(prices)
    end

    ##
    # Calculates the average spread odds for the specified team across all bookmakers.
    # @param [String] team_name - The name of the team for which to calculate average spread odds.
    # @return [Float, nil] The average spread odds, or nil if no data is available.
    def average_spread_odds(team_name)
      entries = extract_market('spreads').compact.select { |o| o['name'] == team_name }
      average(entries.pluck('price'))
    end

    ##
    # Returns the most common spread point value across all bookmakers.
    # @return [Numeric, nil] The mode of spread points, or nil if no spread points are available.
    def consensus_spread_point
      points = extract_market('spreads').compact.pluck('point').compact
      mode(points)
    end

    ##
    # Calculates the average odds for total bets (e.g., "Over" or "Under") with the specified name across all bookmakers.
    # @param [String] name - The name of the total bet outcome ("Over" or "Under").
    # @return [Float, nil] The average odds for the specified total bet, or nil if no odds are available.
    def average_total_odds(name)
      entries = extract_market('totals').compact.select { |o| o['name'] == name }
      average(entries.pluck('price'))
    end

    ##
    # Returns the most common total points line across all bookmakers.
    # @return [Numeric, nil] The mode of total points, or nil if unavailable.
    def consensus_total_point
      points = extract_market('totals').compact.pluck('point').compact
      mode(points)
    end

    ##
    # Retrieves an array of prices for a given team from the specified market across all bookmakers.
    # @param [String] market_key The key identifying the market type (e.g., 'spreads', 'h2h').
    # @param [String] team_name The name of the team whose prices are to be extracted.
    # @return [Array<Numeric>] An array of price values for the specified team; empty if none found.
    def extract_prices(market_key, team_name)
      extract_market(market_key).compact.select { |o| o['name'] == team_name }.pluck('price')
    end

    ##
    # Extracts all outcome entries for a given market key from each bookmaker.
    # @param [String] market_key - The key identifying the market to extract (e.g., 'spreads', 'totals').
    # @return [Array<Hash>] An array of outcome hashes from all matching markets across bookmakers.
    # Returns an empty array if no outcomes are found.
    def extract_market(market_key)
      @bookmakers.flat_map do |book|
        market = (book['markets'] || []).find { |m| m['key'] == market_key }
        market ? market['outcomes'] : []
      end
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
