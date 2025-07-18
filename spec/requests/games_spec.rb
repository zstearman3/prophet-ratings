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
end
