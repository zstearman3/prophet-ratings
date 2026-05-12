# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OddsApi::Importer, type: :service do
  describe '#call' do
    let(:season) { create(:season, :current) }
    let(:home_team) { create(:team, school: 'UAB', slug: 'uab', the_odds_api_team_id: 'par_home') }
    let(:away_team) { create(:team, school: 'North Texas', slug: 'north-texas', the_odds_api_team_id: 'par_away') }
    let(:home_team_season) { create(:team_season, team: home_team, season:) }
    let(:away_team_season) { create(:team_season, team: away_team, season:) }
    let(:start_time) { Time.zone.parse('2026-03-01T17:01:26Z') }
    let!(:game) do
      create(
        :game,
        season:,
        start_time:,
        status: :scheduled,
        home_team_name: home_team.school,
        away_team_name: away_team.school
      )
    end
    let!(:home_team_game) { create(:team_game, game:, team: home_team, team_season: home_team_season, home: true) }
    let!(:away_team_game) { create(:team_game, game:, team: away_team, team_season: away_team_season, home: false) }
    let!(:home_alias) { create(:team_alias, team: home_team, value: 'UAB Blazers', source: 'backfill') }
    let!(:away_alias) { create(:team_alias, team: away_team, value: 'North Texas Mean Green', source: 'backfill') }

    let(:payload) do
      [
        {
          id: 'game-1',
          commence_time: '2026-03-01T17:01:26Z',
          home_team: 'UAB Blazers',
          away_team: 'North Texas Mean Green',
          bookmakers: [
            {
              key: 'betmgm',
              title: 'BetMGM',
              last_update: '2026-03-01T19:02:20Z',
              markets: [
                {
                  key: 'h2h',
                  last_update: '2026-03-01T19:02:20Z',
                  outcomes: [
                    { name: 'North Texas Mean Green', price: 120 },
                    { name: 'UAB Blazers', price: -135 }
                  ]
                },
                {
                  key: 'spreads',
                  last_update: '2026-03-01T19:02:20Z',
                  outcomes: [
                    { name: 'UAB Blazers', price: -110, point: -2.5 },
                    { name: 'North Texas Mean Green', price: -110, point: 2.5 }
                  ]
                },
                {
                  key: 'totals',
                  last_update: '2026-03-01T19:02:20Z',
                  outcomes: [
                    { name: 'Over', price: -130, point: 121.5 },
                    { name: 'Under', price: 100, point: 121.5 }
                  ]
                }
              ]
            }
          ]
        }
      ]
    end

    it 'imports game odds and bookmaker odds from the symbolized payload shape' do
      described_class.new(payload).call

      game_odd = game.reload.game_odd

      aggregate_failures do
        expect(game_odd).to be_present
        expect(game_odd.moneyline_home).to eq(-135)
        expect(game_odd.moneyline_away).to eq(120)
        expect(game_odd.spread_point.to_f).to eq(-2.5)
        expect(game_odd.spread_home_odds).to eq(-110)
        expect(game_odd.spread_away_odds).to eq(-110)
        expect(game_odd.total_points.to_f).to eq(121.5)
        expect(game_odd.total_over_odds).to eq(-130)
        expect(game_odd.total_under_odds).to eq(100)
        expect(game.bookmaker_odds.count).to eq(6)
      end

      over = game.bookmaker_odds.find_by(bookmaker: 'BetMGM', market: 'totals', team_name: 'Over')
      home_moneyline = game.bookmaker_odds.find_by(bookmaker: 'BetMGM', market: 'h2h', team_name: 'UAB Blazers')

      aggregate_failures do
        expect(over.team_side).to eq('over')
        expect(over.value.to_f).to eq(121.5)
        expect(over.odds).to eq(-130)
        expect(home_moneyline.team_side).to eq('home')
        expect(home_moneyline.value).to be_nil
        expect(home_moneyline.odds).to eq(-135)
      end
    end

    it 'updates existing rows instead of duplicating them on repeat imports' do
      described_class.new(payload).call

      updated_payload = [
        payload.first.merge(
          bookmakers: [
            payload.first[:bookmakers].first.merge(
              last_update: '2026-03-01T19:10:00Z',
              markets: [
                {
                  key: 'h2h',
                  last_update: '2026-03-01T19:10:00Z',
                  outcomes: [
                    { name: 'North Texas Mean Green', price: 110 },
                    { name: 'UAB Blazers', price: -125 }
                  ]
                },
                {
                  key: 'spreads',
                  last_update: '2026-03-01T19:10:00Z',
                  outcomes: [
                    { name: 'UAB Blazers', price: -105, point: -1.5 },
                    { name: 'North Texas Mean Green', price: -115, point: 1.5 }
                  ]
                },
                {
                  key: 'totals',
                  last_update: '2026-03-01T19:10:00Z',
                  outcomes: [
                    { name: 'Over', price: -120, point: 122.5 },
                    { name: 'Under', price: -102, point: 122.5 }
                  ]
                }
              ]
            )
          ]
        )
      ]

      expect do
        described_class.new(updated_payload).call
      end.not_to change(GameOdd, :count)

      expect(BookmakerOdd.count).to eq(6)

      game_odd = game.reload.game_odd
      over = game.bookmaker_odds.find_by(bookmaker: 'BetMGM', market: 'totals', team_name: 'Over')

      aggregate_failures do
        expect(game_odd.moneyline_home).to eq(-125)
        expect(game_odd.moneyline_away).to eq(110)
        expect(game_odd.spread_point.to_f).to eq(-1.5)
        expect(game_odd.total_points.to_f).to eq(122.5)
        expect(over.odds).to eq(-120)
        expect(over.value.to_f).to eq(122.5)
      end
    end
  end
end
