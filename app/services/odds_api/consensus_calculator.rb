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

    def average_moneyline(team_name)
      prices = extract_prices('h2h', team_name)
      average(prices)
    end

    def average_spread_odds(team_name)
      entries = extract_market('spreads').compact.select { |o| o['name'] == team_name }
      average(entries.pluck('price'))
    end

    def consensus_spread_point
      points = extract_market('spreads').compact.pluck('point').compact
      mode(points)
    end

    def average_total_odds(name)
      entries = extract_market('totals').compact.select { |o| o['name'] == name }
      average(entries.pluck('price'))
    end

    def consensus_total_point
      points = extract_market('totals').compact.pluck('point').compact
      mode(points)
    end

    def extract_prices(market_key, team_name)
      extract_market(market_key).compact.select { |o| o['name'] == team_name }.pluck('price')
    end

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
