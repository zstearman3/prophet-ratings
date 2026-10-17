# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin prediction evaluations', type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:season) { create(:season) }
  let!(:version) { create(:ratings_config_version) }
  let(:path) { '/admin/prediction_evaluation' }
  let(:filters) { { season_id: season.id, model_id: version.id } }

  it 'requires sign-in for HTML and CSV' do
    get path
    expect(response).to redirect_to(new_user_session_path)
    get "#{path}.csv"
    expect(response).to have_http_status(:unauthorized)
  end

  it 'denies non-admin users for HTML and CSV' do
    sign_in create(:user)
    get path
    expect(response).to have_http_status(:not_found)
    get "#{path}.csv"
    expect(response).to have_http_status(:not_found)
  end

  context 'when signed in as an admin' do
    before { sign_in create(:user, :admin) }

    it 'links from the season admin and renders honest empty results' do
      get "/admin/season/#{season.id}"
      expect(response.body).to include('Evaluate predictions')
      get path, params: filters
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('No eligible predictions', '0 evaluated', 'Verified pregame')
    end

    it 'labels exploratory modes and exports an empty CSV without chart dependencies' do
      get path, params: filters.merge(mode: 'legacy_unverified')
      expect(response.body).to include('Exploratory results only')
      get "#{path}.csv", params: filters
      expect(response).to have_http_status(:ok)
      expect(response.body).to start_with('team_id,school,games,avg_pace_residual,stddev_pace_residual')
    end

    it 'rejects invalid dates, out-of-season windows, unknown modes and missing models' do
      [{ from: 'garbage' }, { from: (season.end_date + 1).iso8601 }, { mode: 'all' }].each do |invalid|
        get path, params: filters.merge(invalid)
        expect(response).to have_http_status(:unprocessable_content)
      end
      get path, params: filters.merge(model_id: 0)
      expect(response).to have_http_status(:not_found)
    end

    it 'renders charts and scorecards from stored outcomes, including a comparison' do
      game = create(:game, season:, start_time: season.start_date + 5.days, home_team_score: 80, away_team_score: 70, minutes: 45,
                           possessions: 90)
      snapshots = create_list(:team_season, 2, season:).map do |team|
        create(:team_rating_snapshot, team_season: team, ratings_config_version: version)
      end
      create(:prediction, game:, ratings_config_version: version, home_team_snapshot: snapshots.first, away_team_snapshot: snapshots.last,
                          home_score: 84, away_score: 72, pace: 78, home_win_probability: 0.75)
      get path, params: filters.merge(mode: 'legacy_unverified', comparison_id: version.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('1 evaluated', 'Brier score', 'Win probability calibration', 'Common-game comparison',
                                       'new Chartkick["ScatterChart"]')
    end
  end
end
