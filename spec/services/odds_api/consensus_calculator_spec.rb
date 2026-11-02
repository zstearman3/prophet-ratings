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
    it 'returns integer probability-mean odds at the modal lines and a fetch timestamp' do
      expect(calculator.consensus).to include(
        fetched_at: be_present, moneyline_home: -147, moneyline_away: 132,
        spread_point: -3.5, spread_home_odds: -110, spread_away_odds: -110,
        total_points: 127.5, total_over_odds: -107, total_under_odds: -112
      )
    end

    it 'leaves every market unavailable when market data is missing' do
      calc = described_class.new(bookmakers: [{ key: 'book3', title: 'Book3', markets: [] }], home_team:, away_team:)
      expect(calc.consensus).to include(moneyline_home: nil, moneyline_away: nil,
                                        spread_point: nil, spread_home_odds: nil, spread_away_odds: nil,
                                        total_points: nil, total_over_odds: nil, total_under_odds: nil)
    end

    it 'uses the home team spread regardless of outcome order or a more frequent away line' do
      bookmakers.first[:markets][1][:outcomes].reverse!
      bookmakers.last[:markets][1][:outcomes][1][:point] = 3.5

      expect(calculator.consensus[:spread_point]).to eq(-3.5)
    end

    it 'accepts source labels aligned to local sides and leaves an absent home spread unavailable' do
      bookmakers.each { |book| book[:markets][1][:outcomes].reject! { |outcome| outcome[:name] == 'UAB Blazers' } }
      calc = described_class.new(bookmakers:, home_team: 'UAB Blazers', away_team: 'North Texas Mean Green')

      expect(calc.consensus).to include(moneyline_home: -147, moneyline_away: 132, spread_point: nil)
    end

    it 'averages mixed signs in probability space and canonicalizes even money' do
      [[100, -102, -101], [100, -100, 100], [-100, -100, 100], [130, 135, 132]].each do |first, second, expected|
        bookmakers.first[:markets][0][:outcomes][0][:price] = first
        bookmakers.last[:markets][0][:outcomes][0][:price] = second
        expect(calculator.consensus[:moneyline_home]).to eq(expected)
      end
    end

    it 'ignores unusable prices without coercing them and preserves a lone valid quote' do
      [nil, '150', 0, 99, -99, Float::NAN, Float::INFINITY, -Float::INFINITY, Complex(100, 1)].each do |invalid|
        bookmakers.first[:markets][0][:outcomes][0][:price] = invalid
        bookmakers.last[:markets][0][:outcomes][0][:price] = -145
        expect(calculator.consensus[:moneyline_home]).to eq(-145)
        bookmakers.last[:markets][0][:outcomes][0][:price] = invalid
        expect(calculator.consensus[:moneyline_home]).to be_nil
      end
    end

    it 'keeps spread and total prices at the selected line even when another line offers a side' do
      bookmakers.last[:markets][1][:outcomes][0][:price] = 120
      bookmakers.first[:markets][1][:outcomes].pop
      bookmakers.last[:markets][2][:outcomes].each { |outcome| outcome[:point] = 130 }
      bookmakers.first[:markets][2][:outcomes].pop

      expect(calculator.consensus).to include(spread_point: -3.5, spread_home_odds: -110,
                                              spread_away_odds: nil, total_points: 130,
                                              total_over_odds: -110, total_under_odds: -110)
    end

    it 'leaves a total side unavailable when only another line offers it' do
      bookmakers.first[:markets][2][:outcomes].pop
      bookmakers.last[:markets][2][:outcomes] = [{ name: 'Under', point: 130, price: 150 }]

      expect(calculator.consensus).to include(total_points: 127.5, total_over_odds: -105, total_under_odds: nil)
    end

    it 'excludes invalid prices in every market while retaining valid selected lines' do
      bookmakers.each do |book|
        book[:markets].each do |market|
          market[:outcomes].each { |outcome| outcome[:price] = -1 }
        end
      end

      expect(calculator.consensus).to include(moneyline_home: nil, moneyline_away: nil,
                                              spread_point: -3.5, spread_home_odds: nil, spread_away_odds: nil,
                                              total_points: 127.5, total_over_odds: nil, total_under_odds: nil)
    end

    it 'does not price a selected line from a non-real point equal to that line' do
      bookmakers.first[:markets][1][:outcomes][0].merge!(point: 0, price: -110)
      bookmakers.last[:markets][1][:outcomes][0].merge!(point: Complex(0, 0), price: 200)

      expect(calculator.consensus).to include(spread_point: 0, spread_home_odds: -110)
    end

    it 'rejects missing and nonfinite lines, accepts zero, and supports string keys' do
      [nil, '0', Float::NAN, Float::INFINITY, Complex(0, 1)].each do |invalid|
        bookmakers.first[:markets][1][:outcomes][0][:point] = invalid
        bookmakers.last[:markets][1][:outcomes][0][:point] = 0
        bookmakers.last[:markets][1][:outcomes][1][:point] = 0
        bookmakers.each do |book|
          book[:markets][2][:outcomes].each { |outcome| outcome[:point] = invalid }
        end
        expect(calculator.consensus).to include(spread_point: 0, spread_home_odds: -115,
                                                spread_away_odds: -105, total_points: nil,
                                                total_over_odds: nil, total_under_odds: nil)
      end
      string_books = bookmakers.map(&:deep_stringify_keys)
      expect(described_class.new(bookmakers: string_books, home_team:, away_team:).consensus)
        .to include(spread_point: 0, spread_home_odds: -115)
    end
  end
end
