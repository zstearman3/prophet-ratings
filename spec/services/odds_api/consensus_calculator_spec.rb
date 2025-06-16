# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OddsApi::ConsensusCalculator, type: :service do
  subject(:calculator) { described_class.new(bookmakers:, home_team:, away_team:) }

  let(:home_team) { instance_double(Team, the_odds_api_team_id: 'HOME_ID') }
  let(:away_team) { instance_double(Team, the_odds_api_team_id: 'AWAY_ID') }

  let(:bookmakers) do
    [
      {
        'bookmaker' => 'Book1',
        'markets' => [
          {
            'key' => 'h2h',
            'outcomes' => [
              { 'name' => 'HOME_ID', 'price' => -150 },
              { 'name' => 'AWAY_ID', 'price' => 130 }
            ]
          },
          {
            'key' => 'spreads',
            'outcomes' => [
              { 'name' => 'HOME_ID', 'point' => -3.5, 'price' => -110 },
              { 'name' => 'AWAY_ID', 'point' => 3.5, 'price' => -110 }
            ]
          }
        ]
      },
      {
        'bookmaker' => 'Book2',
        'markets' => [
          {
            'key' => 'h2h',
            'outcomes' => [
              { 'name' => 'HOME_ID', 'price' => -145 },
              { 'name' => 'AWAY_ID', 'price' => 135 }
            ]
          },
          {
            'key' => 'spreads',
            'outcomes' => [
              { 'name' => 'HOME_ID', 'point' => -4.0, 'price' => -115 },
              { 'name' => 'AWAY_ID', 'point' => 4.0, 'price' => -105 }
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

    it 'handles missing market data gracefully for moneyline_home' do
      bad_bookmakers = [
        { 'bookmaker' => 'Book3', 'markets' => [] }
      ]
      calc = described_class.new(bookmakers: bad_bookmakers, home_team:, away_team:)
      consensus = calc.consensus
      expect(consensus[:moneyline_home]).to be_nil
    end

    it 'handles missing market data gracefully for spread_point' do
      bad_bookmakers = [
        { 'bookmaker' => 'Book3', 'markets' => [] }
      ]
      calc = described_class.new(bookmakers: bad_bookmakers, home_team:, away_team:)
      consensus = calc.consensus
      expect(consensus[:spread_point]).to be_nil
    end
  end

  # Add more specs for edge cases as needed
end
