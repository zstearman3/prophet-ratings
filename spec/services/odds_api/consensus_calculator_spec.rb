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
    it 'returns a hash with consensus odds' do
      consensus = calculator.consensus
      expect(consensus).to include(:fetched_at, :moneyline_home, :moneyline_away, :spread_point, :spread_home_odds)
    end

    it 'averages moneylines for home' do
      consensus = calculator.consensus
      expect(consensus[:moneyline_home]).to eq(-147.5)
    end

    it 'averages moneylines for away' do
      consensus = calculator.consensus
      expect(consensus[:moneyline_away]).to eq(132.5)
    end

    it 'returns mode for spread point' do
      consensus = calculator.consensus
      expect(consensus[:spread_point]).to eq(-3.5)
    end

    it 'averages spread home odds' do
      consensus = calculator.consensus
      expect(consensus[:spread_home_odds]).to eq(-112.5)
    end

    it 'returns the consensus total line and odds' do
      consensus = calculator.consensus
      expect(consensus[:total_points]).to eq(127.5)
      expect(consensus[:total_over_odds]).to eq(-107.5)
      expect(consensus[:total_under_odds]).to eq(-112.5)
    end

    it 'handles missing market data gracefully for moneyline_home' do
      bad_bookmakers = [
        { key: 'book3', title: 'Book3', markets: [] }
      ]
      calc = described_class.new(bookmakers: bad_bookmakers, home_team:, away_team:)
      consensus = calc.consensus
      expect(consensus[:moneyline_home]).to be_nil
    end

    it 'handles missing market data gracefully for spread_point' do
      bad_bookmakers = [
        { key: 'book3', title: 'Book3', markets: [] }
      ]
      calc = described_class.new(bookmakers: bad_bookmakers, home_team:, away_team:)
      consensus = calc.consensus
      expect(consensus[:spread_point]).to be_nil
    end
  end

  # Add more specs for edge cases as needed
end
