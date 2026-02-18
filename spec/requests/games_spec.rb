# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Games' do
  describe 'GET /schedule' do
    it 'returns http success' do
      season = create(:season, :current)
      team = create(:team)
      team_season = create(:team_season, team:, season:)
      game = create(:game, start_time: Date.current.beginning_of_day + 12.hours, status: :final, minutes: 40, home_team_score: 70,
                           away_team_score: 65, location: 'Arena', season:)
      create(:team_game, game:, team:, team_season:)
      get '/games/schedule', params: { date: Date.current.to_s }
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /games/:id' do
    let(:season) { create(:season, :current) }
    let(:home_team) { create(:team, school: 'Home Team', slug: 'home-team') }
    let(:away_team) { create(:team, school: 'Away Team', slug: 'away-team') }
    let(:home_team_season) { create(:team_season, team: home_team, season:) }
    let(:away_team_season) { create(:team_season, team: away_team, season:) }
    let(:location) { nil }
    let(:game) do
      create(
        :game,
        season:,
        start_time: Date.current.beginning_of_day + 12.hours,
        status: :final,
        minutes: 40,
        home_team_score: 70,
        away_team_score: 65,
        home_team_name: home_team.school,
        away_team_name: away_team.school,
        location:
      )
    end

    before do
      create(:team_game, game:, team: home_team, team_season: home_team_season, home: true, points: 70)
      create(:team_game, game:, team: away_team, team_season: away_team_season, home: false, points: 65)
    end

    context 'when location is blank' do
      let(:location) { '' }

      it 'does not render the location header' do
        get "/games/#{game.id}"

        expect(response).to have_http_status(:success)
        expect(response.body).not_to include('Location:')
      end
    end

    context 'when location is present' do
      let(:location) { 'Test Arena' }

      it 'renders the location header and value' do
        get "/games/#{game.id}"

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Location: Test Arena')
      end
    end
  end
end
