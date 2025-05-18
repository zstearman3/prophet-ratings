require 'rails_helper'

RSpec.describe "Matchups", type: :request do
  describe "GET /show" do
    it "returns http success" do
      season = create(:season)
      team = create(:team)
      create(:team_season, team: team, season: season)
      get "/matchup"
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /submit" do
    it "returns http success (turbo_stream)" do
      season = create(:season)
      team1 = create(:team)
      team2 = create(:team)
      ts1 = create(:team_season, team: team1, season: season)
      ts2 = create(:team_season, team: team2, season: season)
      config = create(:ratings_config_version)
      create(:team_rating_snapshot, team_season: ts1, ratings_config_version: config)
      create(:team_rating_snapshot, team_season: ts2, ratings_config_version: config)
      post "/matchup/submit", params: { home_team_id: ts1.id, away_team_id: ts2.id, neutral: '0', action_type: 'predict' }, as: :turbo_stream
      expect(response).to have_http_status(:success)
    end
  end

end
