# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OddsApi::SyncService, type: :service do
  subject(:service) { described_class.new(client:) }

  let(:client) { instance_double(OddsApi::Client, fetch_odds: payload) }
  let(:season) { create(:season, :current) }
  let(:home_team) { create(:team, school: 'UAB', slug: 'uab', the_odds_api_team_id: 'par_home') }
  let(:away_team) { create(:team, school: 'North Texas', slug: 'north-texas', the_odds_api_team_id: 'par_away') }
  let(:home_team_season) { create(:team_season, team: home_team, season:) }
  let(:away_team_season) { create(:team_season, team: away_team, season:) }
  let!(:game) do
    create(
      :game,
      season:,
      start_time: Time.zone.parse('2026-03-01T17:01:26Z'),
      status: :scheduled,
      home_team_name: home_team.school,
      away_team_name: away_team.school
    )
  end
  let(:home_team_game) { create(:team_game, game:, team: home_team, team_season: home_team_season, home: true) }
  let(:away_team_game) { create(:team_game, game:, team: away_team, team_season: away_team_season, home: false) }
  let(:home_alias) { create(:team_alias, team: home_team, value: 'UAB Blazers', source: 'backfill') }
  let(:away_alias) { create(:team_alias, team: away_team, value: 'North Texas Mean Green', source: 'backfill') }

  let(:fixture_payload) do
    JSON.parse(
      Rails.root.join('spec/fixtures/odds_api/ncaab_odds_example.json').read,
      symbolize_names: true
    )
  end

  before do
    home_team_game
    away_team_game
    home_alias
    away_alias
  end

  describe '#call' do
    context 'when the API returns odds' do
      let(:payload) { fixture_payload }

      it 'fetches and imports returned odds' do
        result = service.call

        aggregate_failures do
          expect(client).to have_received(:fetch_odds)
          expect(result.fetched_count).to eq(1)
          expect(result.imported_count).to eq(1)
          expect(result.failed_count).to eq(0)
          expect(result.failures).to be_empty
          expect(game.reload.game_odd).to be_present
          expect(game.bookmaker_odds.count).to eq(48)
        end
      end
    end

    context 'when some odds payloads cannot be matched' do
      let(:payload) do
        unmatched_game = fixture_payload.first.merge(
          id: 'unmatched-game',
          home_team: 'Unknown Home',
          away_team: 'Unknown Away'
        )

        [fixture_payload.first, unmatched_game]
      end

      it 'imports matched games and reports unmatched failures' do
        result = service.call

        aggregate_failures do
          expect(result.fetched_count).to eq(2)
          expect(result.imported_count).to eq(1)
          expect(result.failed_count).to eq(1)
          expect(result.failures.first).to include(
            odds_api_game_id: 'unmatched-game',
            home_team: 'Unknown Home',
            away_team: 'Unknown Away',
            commence_time: '2026-03-01T17:01:26Z',
            error_class: 'ActiveRecord::RecordNotFound'
          )
          expect(result.failures.first[:message]).to eq('Could not match game teams from odds payload')
          expect(game.reload.game_odd).to be_present
        end
      end
    end

    context 'when the API returns an empty array' do
      let(:payload) { [] }

      it 'returns a successful empty result without importing rows' do
        result = nil

        expect do
          result = service.call
        end.not_to change(GameOdd, :count)

        aggregate_failures do
          expect(result.fetched_count).to eq(0)
          expect(result.imported_count).to eq(0)
          expect(result.failed_count).to eq(0)
          expect(result.failures).to be_empty
        end
      end
    end
  end
end
