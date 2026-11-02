# frozen_string_literal: true

module OddsApi
  class ConsensusCalculator
    def initialize(bookmakers:, home_team:, away_team:)
      @bookmakers = Array(bookmakers)
      @home_names = outcome_names(home_team)
      @away_names = outcome_names(away_team)
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

    def average_moneyline(team_names)
      average_prices(entries_for('h2h', team_names))
    end

    def average_spread_odds(team_names)
      line = consensus_spread_point
      return unless line

      prices_at_line('spreads', team_names, team_names == @home_names ? line : -line)
    end

    def consensus_spread_point
      mode(entries_for('spreads', @home_names).map { |outcome| value_for(outcome, :point) })
    end

    def average_total_odds(name)
      line = consensus_total_point
      return unless line

      prices_at_line('totals', [name], line)
    end

    def consensus_total_point
      mode(extract_market('totals').map { |outcome| value_for(outcome, :point) })
    end

    def prices_at_line(market_key, names, line)
      average_prices(entries_for(market_key, names).select { |outcome| value_for(outcome, :point) == line })
    end

    def entries_for(market_key, names)
      extract_market(market_key).select { |outcome| names.include?(value_for(outcome, :name)) }
    end

    def average_prices(entries)
      AmericanOdds.consensus(entries.map { |outcome| value_for(outcome, :price) })
    end

    def extract_market(market_key)
      outcomes = @bookmakers.flat_map do |book|
        markets = Array(value_for(book, :markets))
        market = markets.find { |entry| value_for(entry, :key) == market_key }
        market ? Array(value_for(market, :outcomes)) : []
      end
      return outcomes if market_key == 'h2h'

      outcomes.select do |outcome|
        point = value_for(outcome, :point)
        point.is_a?(Numeric) && point.real? && point.finite?
      end
    end

    def outcome_names(team)
      team.is_a?(String) ? [team] : team_identifiers(team)
    end

    def team_identifiers(team)
      candidates = []
      candidates << team.school if team.respond_to?(:school)
      candidates << team.the_odds_api_team_id if team.respond_to?(:the_odds_api_team_id)

      candidates.concat(Array(team.team_aliases).map(&:value)) if team.respond_to?(:team_aliases)

      candidates.compact.map(&:to_s).uniq
    end

    def value_for(hash, key)
      hash[key] || hash[key.to_s]
    end

    def mode(array)
      return nil if array.empty?

      array.group_by(&:itself).max_by { |_, v| v.size }[0]
    end
  end
end
