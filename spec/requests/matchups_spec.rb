# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Matchups' do
  let(:season) { create(:season, :current) }
  let(:team1) { create(:team) }
  let(:team2) { create(:team) }
  let(:ts1) { create(:team_season, team: team1, season:) }
  let(:ts2) { create(:team_season, team: team2, season:) }
  let(:config) { RatingsConfigVersion.ensure_current! }

  describe 'GET /show' do
    it 'returns http success' do
      get '/matchup'
      expect(response).to have_http_status(:success)
    end
  end

  describe 'POST /submit' do
    it 'shows legacy-model errors in the existing results area for both actions', :aggregate_failures do
      legacy = create(:ratings_config_version, name: 'v1.2-default', current: true)
      create(:team_rating_snapshot, team_season: ts1, ratings_config_version: legacy)
      create(:team_rating_snapshot, team_season: ts2, ratings_config_version: legacy)
      # Reproduce a retained version published before the complete configuration contract.
      legacy.update_columns(config: { bundle_name: legacy.name }) # rubocop:disable Rails/SkipsModelValidations

      get '/matchup'
      page = response.parsed_body

      %w[predict simulate].each do |action|
        post '/matchup/submit', params: {
          home_team_id: ts1.id, away_team_id: ts2.id, neutral: '0', upset_modifier: '1.0', action_type: action
        }, as: :turbo_stream

        stream = Nokogiri::HTML(response.parsed_body).at_css('turbo-stream')
        expect(response).to have_http_status(:unprocessable_content)
        expect(stream['action']).to eq('update')
        expect(stream['target']).to eq('prediction_result_frame')
        expect(page.at_css("##{stream['target']}")).not_to be_nil
        expect(stream.at_css('template').text).to include('Model v1.2-default lacks the complete configuration contract')
      end

      expect(legacy.reload.config).to eq('bundle_name' => 'v1.2-default')
      expect(RatingsConfigVersion.current).to eq(legacy)
    end

    it 'returns http success (turbo_stream) when valid' do
      create(:team_rating_snapshot, team_season: ts1, ratings_config_version: config)
      create(:team_rating_snapshot, team_season: ts2, ratings_config_version: config)
      post '/matchup/submit', params: { home_team_id: ts1.id, away_team_id: ts2.id, neutral: '0', action_type: 'predict' },
                              as: :turbo_stream
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Uncalibrated')
    end

    it 'returns http success (turbo_stream) when simulating a valid matchup' do
      create(:team_rating_snapshot, team_season: ts1, ratings_config_version: config)
      create(:team_rating_snapshot, team_season: ts2, ratings_config_version: config)
      post '/matchup/submit', params: { home_team_id: ts1.id, away_team_id: ts2.id, neutral: '0', action_type: 'simulate' },
                              as: :turbo_stream
      expect(response).to have_http_status(:ok)
    end

    it 'returns 422 when upset_modifier is non-numeric' do
      create(:team_rating_snapshot, team_season: ts1, ratings_config_version: config)
      create(:team_rating_snapshot, team_season: ts2, ratings_config_version: config)

      post '/matchup/submit', params: {
        home_team_id: ts1.id,
        away_team_id: ts2.id,
        neutral: '0',
        action_type: 'simulate',
        upset_modifier: 'not-a-number'
      }, as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Upset modifier must be a valid number between 0.1 and 2.0')
    end

    it 'returns 422 when upset_modifier is outside allowed range' do
      create(:team_rating_snapshot, team_season: ts1, ratings_config_version: config)
      create(:team_rating_snapshot, team_season: ts2, ratings_config_version: config)

      post '/matchup/submit', params: {
        home_team_id: ts1.id,
        away_team_id: ts2.id,
        neutral: '0',
        action_type: 'simulate',
        upset_modifier: '2.5'
      }, as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Upset modifier must be between 0.1 and 2.0')
    end

    it 'returns 422 if snapshots are missing' do
      config # Publish an active model but no snapshots
      post '/matchup/submit', params: { home_team_id: ts1.id, away_team_id: ts2.id, neutral: '0', action_type: 'predict' },
                              as: :turbo_stream
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Missing home or away rating snapshot')
    end
  end
end
