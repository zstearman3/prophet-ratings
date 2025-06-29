# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Matchups' do
  describe 'GET /show' do
    it 'returns http success' do
      season = create(:season)
      team = create(:team)
      create(:team_season, team:, season:)
      get '/matchup'
      expect(response).to have_http_status(:success)
    end
  end

  describe 'POST /submit' do
    it 'returns http success (turbo_stream) when valid' do
      season = create(:season)
      team1 = create(:team)
      team2 = create(:team)
      ts1 = create(:team_season, team: team1, season:)
      ts2 = create(:team_season, team: team2, season:)
      config = RatingsConfigVersion.ensure_current!
      create(:team_rating_snapshot, team_season: ts1, ratings_config_version: config)
      create(:team_rating_snapshot, team_season: ts2, ratings_config_version: config)
      post '/matchup/submit', params: { home_team_id: ts1.id, away_team_id: ts2.id, neutral: '0', action_type: 'predict' },
                              as: :turbo_stream
      expect(response).to have_http_status(:ok)
    end

    it 'returns 422 if snapshots are missing' do
      season = create(:season)
      team1 = create(:team)
      team2 = create(:team)
      ts1 = create(:team_season, team: team1, season:)
      ts2 = create(:team_season, team: team2, season:)
      # No snapshots created
      post '/matchup/submit', params: { home_team_id: ts1.id, away_team_id: ts2.id, neutral: '0', action_type: 'predict' },
                              as: :turbo_stream
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Missing home or away rating snapshot')
    end
  end
end
