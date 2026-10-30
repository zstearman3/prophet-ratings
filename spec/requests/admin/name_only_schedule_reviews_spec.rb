# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin name-only schedule conflict review' do
  include Devise::Test::IntegrationHelpers

  include_context 'with name-only schedule conflict'

  let(:path) { admin_schedule_refresh_run_game_schedule_review_path(run, observation) }

  before { sign_in admin }

  it 'shows both participant identities and offers an explicit choice without a reason' do
    observation
    get admin_schedule_refresh_run_path(run)
    expect(response.body).to include('Resolve schedule conflict', path)
    get path
    aggregate_failures do
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Old Visitor', 'New Visitor', 'visitor-old', 'visitor-new', 'old-1')
      expect(response.parsed_body.css('input[type="radio"][checked], textarea, input[name*="reason"]')).to be_empty
      expect(GameScheduleReview.count).to eq(0)
    end
  end

  context 'when only the source team ID changed' do
    let(:incoming_opponent) { 'Old Visitor' }

    it 'shows the different IDs even though the opponent names match' do
      get path
      expect(response.body).to include('visitor-old', 'visitor-new', 'Old Visitor')
      expect(response).to have_http_status(:ok)
    end
  end

  %w[existing incoming].each do |choice|
    it "records the #{choice} choice and offers a retry without retiring the shared game key" do
      fingerprint = schedule_evidence.fingerprint
      patch path, params: { choice:, fingerprint: }
      expect(response).to redirect_to(path)
      follow_redirect!
      aggregate_failures do
        expect(response.body).to include('Approved by admin', 'Retry unfinished dates', 'old-1')
        expect(response.body).not_to include('Retired CBBD')
        expect(GameScheduleReview.last.selected_payload.dig('away', 'external_team_id'))
          .to eq(choice == 'incoming' ? 'visitor-new' : 'visitor-old')
      end
      get admin_schedule_refresh_run_path(run)
      expect(response.body).to include('Schedule conflict resolved', path)
    end
  end

  it 'does not approve a missing choice, a stale comparison or a non-admin request' do
    fingerprint = schedule_evidence.fingerprint
    patch path, params: { fingerprint: }
    expect(response).to have_http_status(:unprocessable_content)
    game.update!(venue_name: 'Changed venue')
    patch path, params: { choice: 'incoming', fingerprint: }
    expect(response).to have_http_status(:unprocessable_content)
    sign_out admin
    sign_in create(:user)
    patch path, params: { choice: 'incoming', fingerprint: }
    expect(response).to have_http_status(:not_found)
    expect(GameScheduleReview.count).to eq(0)
  end
end
