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
    let(:home_team_game) { create(:team_game, game:, team: home_team, team_season: home_team_season, home: true) }
    let(:away_team_game) { create(:team_game, game:, team: away_team, team_season: away_team_season, home: false) }
    let(:home_alias) { create(:team_alias, team: home_team, value: 'UAB Blazers', source: 'backfill') }
    let(:away_alias) { create(:team_alias, team: away_team, value: 'North Texas Mean Green', source: 'backfill') }

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

    let(:updated_payload) do
      [
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
    end

    before do
      home_team_game
      away_team_game
      home_alias
      away_alias
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

    it 'imports the NCAAB fixture adapted from The Odds API published example' do
      fixture_payload = JSON.parse(
        Rails.root.join('spec/fixtures/odds_api/ncaab_odds_example.json').read,
        symbolize_names: true
      )

      described_class.new(fixture_payload).call

      game_odd = game.reload.game_odd

      aggregate_failures do
        expect(game_odd.moneyline_home).to eq(-291)
        expect(game_odd.moneyline_away).to eq(236)
        expect(game_odd.spread_point.to_f).to eq(-6.5)
        expect(game_odd.spread_home_odds).to eq(-111)
        expect(game_odd.spread_away_odds).to eq(-109)
        # 12 bookmakers x 2 markets x 2 outcomes = 48
        expect(game.bookmaker_odds.count).to eq(48)
      end
    end

    it 'accepts the empty odds fixture without importing rows' do
      fixture_payload = JSON.parse(
        Rails.root.join('spec/fixtures/odds_api/empty_odds.json').read,
        symbolize_names: true
      )

      expect do
        described_class.new(fixture_payload).call
      end.not_to change(GameOdd, :count)
    end

    context 'when providers disagree on neutral-site sides' do
      before do
        game.update!(neutral: true)
        payload.first.merge!(home_team: 'North Texas Mean Green', away_team: 'UAB Blazers')
        spreads = payload.first[:bookmakers].first[:markets][1][:outcomes]
        spreads[0][:price] = -105
        spreads[1][:price] = -115
        spreads.reverse!
      end

      it 'keeps prices, spread sign and bookmaker sides aligned with the stored participants on repeat imports' do
        2.times { described_class.new(payload).call }

        aggregate_failures do
          expect(game.reload.game_odd).to have_attributes(moneyline_home: -135, moneyline_away: 120,
                                                          spread_point: -2.5, spread_home_odds: -105, spread_away_odds: -115,
                                                          total_points: 121.5)
          expect(game.bookmaker_odds.count).to eq(6)
          expect(game.bookmaker_odds.find_by(market: 'h2h', team_name: 'UAB Blazers')).to have_attributes(team_side: 'home', odds: -135)
          expect(game.bookmaker_odds.find_by(market: 'spreads', team_name: 'North Texas Mean Green'))
            .to have_attributes(team_side: 'away', value: 2.5, odds: -115)
          expect(game).to have_attributes(home_team_name: 'UAB', away_team_name: 'North Texas', start_time:)
        end
      end

      it 'does not reverse sides for a game without neutral-site evidence' do
        game.update!(neutral: nil)

        expect { described_class.new(payload).call }.to raise_error(ActiveRecord::RecordNotFound, /Could not find game/)
        expect(GameOdd.count).to eq(0)
      end

      it 'accepts canonical neutral venue evidence without the legacy flag' do
        game.update!(neutral: nil, venue_type: 'neutral')

        expect { described_class.new(payload).call }.to change(GameOdd, :count).by(1)
      end

      context 'when tip times straddle an Eastern schedule-date boundary' do
        let(:start_time) { Time.zone.parse('2026-11-02T04:59:00Z') }

        before { payload.first[:commence_time] = '2026-11-02T07:00:00Z' }

        it 'matches a unique neutral game within three hours across midnight' do
          expect { described_class.new(payload).call }.to change(GameOdd, :count).by(1)
          expect(game.reload.start_time).to eq(start_time)
        end

        it 'rejects a nearby game when neutral-site evidence is missing even with matching sides' do
          game.update!(neutral: false)
          payload.first.merge!(home_team: 'UAB Blazers', away_team: 'North Texas Mean Green')

          expect { described_class.new(payload).call }.to raise_error(ActiveRecord::RecordNotFound)
          expect(GameOdd.count).to eq(0)
        end

        it 'rejects cross-date matches beyond the time tolerance' do
          payload.first[:commence_time] = '2026-11-02T08:00:00Z'

          expect { described_class.new(payload).call }.to raise_error(ActiveRecord::RecordNotFound)
          expect(GameOdd.count).to eq(0)
        end

        it 'rejects ambiguity between an ordered same-date match and a nearby reversed neutral match' do
          other = create(:game, season:, start_time: Time.zone.parse('2026-11-02T07:00:00Z'),
                                home_team_name: away_team.school, away_team_name: home_team.school)
          create(:team_game, game: other, team: away_team, team_season: away_team_season, home: true)
          create(:team_game, game: other, team: home_team, team_season: home_team_season, home: false)

          expect { described_class.new(payload).call }.to raise_error(ActiveRecord::RecordNotFound, /Multiple games/)
          expect(GameOdd.count).to eq(0)
        end
      end
    end

    it 'rejects multiple participant matches instead of choosing an arbitrary game' do
      duplicate = create(:game, season:, start_time:, home_team_name: 'Other home label', away_team_name: 'Other away label')
      create(:team_game, game: duplicate, team: home_team, team_season: home_team_season, home: true)
      create(:team_game, game: duplicate, team: away_team, team_season: away_team_season, home: false)

      expect { described_class.new(payload).call }.to raise_error(ActiveRecord::RecordNotFound, /Multiple games/)
      expect(GameOdd.count).to eq(0)
      expect(BookmakerOdd.count).to eq(0)
    end
  end
end
