# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OddsApi::ConsensusCalculator, type: :service do
  subject(:calculator) { described_class.new(bookmakers:, home_team:, away_team:) }

  let(:home_alias) { instance_double(TeamAlias, value: 'UAB Blazers') }
  let(:away_alias) { instance_double(TeamAlias, value: 'North Texas Mean Green') }
  let(:home_team) { instance_double(Team, school: 'UAB', the_odds_api_team_id: 'HOME_ID', team_aliases: [home_alias]) }
  let(:away_team) { instance_double(Team, school: 'North Texas', the_odds_api_team_id: 'AWAY_ID', team_aliases: [away_alias]) }

  let(:bookmakers) do
    [
      {
        key: 'book1',
        title: 'Book1',
        markets: [
          {
            key: 'h2h',
            outcomes: [
              { name: 'UAB Blazers', price: -150 },
              { name: 'North Texas Mean Green', price: 130 }
            ]
          },
          {
            key: 'spreads',
            outcomes: [
              { name: 'UAB Blazers', point: -3.5, price: -110 },
              { name: 'North Texas Mean Green', point: 3.5, price: -110 }
            ]
          },
          {
            key: 'totals',
            outcomes: [
              { name: 'Over', point: 127.5, price: -105 },
              { name: 'Under', point: 127.5, price: -115 }
            ]
          }
        ]
      },
      {
        key: 'book2',
        title: 'Book2',
        markets: [
          {
            key: 'h2h',
            outcomes: [
              { name: 'UAB Blazers', price: -145 },
              { name: 'North Texas Mean Green', price: 135 }
            ]
          },
          {
            key: 'spreads',
            outcomes: [
              { name: 'UAB Blazers', point: -4.0, price: -115 },
              { name: 'North Texas Mean Green', point: 4.0, price: -105 }
            ]
          },
          {
            key: 'totals',
            outcomes: [
              { name: 'Over', point: 127.5, price: -110 },
              { name: 'Under', point: 127.5, price: -110 }
            ]
          }
        ]
      }
    ]
  end

  describe '#consensus' do
    it 'returns averaged odds, the modal spread and a fetch timestamp' do
      expect(calculator.consensus).to include(
        fetched_at: be_present, moneyline_home: -147.5, moneyline_away: 132.5,
        spread_point: -3.5, spread_home_odds: -112.5,
        total_points: 127.5, total_over_odds: -107.5, total_under_odds: -112.5
      )
    end

    it 'leaves moneyline and spread unavailable when market data is missing' do
      calc = described_class.new(bookmakers: [{ key: 'book3', title: 'Book3', markets: [] }], home_team:, away_team:)
      expect(calc.consensus).to include(moneyline_home: nil, spread_point: nil)
    end
  end
end
