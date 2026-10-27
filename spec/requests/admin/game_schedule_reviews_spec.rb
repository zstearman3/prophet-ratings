# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin schedule conflict review' do
  include Devise::Test::IntegrationHelpers

  include_context 'with schedule conflict evidence'

  let(:path) { admin_schedule_refresh_run_game_schedule_review_path(run, observation) }

  before { sign_in admin }

  it 'offers a read-only comparison with Eastern dates and no written justification' do
    observation
    get admin_schedule_refresh_run_path(run)
    expect(response.body).to include('Resolve schedule conflict', path)
    get path
    aggregate_failures do
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Synthetic Home', 'Synthetic Away', 'old-1', 'new-2', '2026-12-08', '2026-12-09', 'Time unknown')
      expect(response.parsed_body.css('textarea, input[name*="reason"]')).to be_empty
      expect(response.parsed_body.at_css('form[data-turbo="false"]')).to be_present
      expect(GameScheduleReview.count).to eq(0)
    end
  end

  %w[existing incoming].each do |choice|
    it "approves the #{choice} entry and keeps the original failed date available for retry" do
      fingerprint = schedule_evidence.fingerprint
      patch path, params: { choice:, fingerprint: }
      expect(response).to redirect_to(path)
      follow_redirect!
      expect(response.body).to include('Approved by admin', 'Retry unfinished dates')
      get admin_schedule_refresh_run_path(run)
      expect(response.body).to include('Schedule conflict resolved', path)
      expect(run.reload.pending_dates).to eq([date.iso8601])
    end

    it "shows and records effective #{choice} schedule values including manual corrections" do
      observation
      game.update!(start_time: '2026-12-09T01:30:00Z', venue_name: 'Manually corrected venue',
                   venue_source: 'manual_override', venue_confidence: 'manual')
      get path
      cards = response.parsed_body.css('fieldset label')
      expect(cards.first.text).to include('8:30 PM EST', 'Manually corrected venue')
      expect(cards.last.text).to include('Time unknown', 'Manually corrected venue')
      patch path, params: { choice:, fingerprint: schedule_evidence.fingerprint }
      expect(response).to redirect_to(path)
      review = GameScheduleReview.last
      expect(review.selected_schedule).to include('venue_name' => 'Manually corrected venue',
                                                  'start_time' => game.reload.start_time.iso8601,
                                                  'schedule_date' => game.schedule_date.iso8601)
    end
  end

  it 'requires a choice and rejects a stale comparison without creating a review' do
    fingerprint = schedule_evidence.fingerprint
    patch path, params: { fingerprint: }
    expect(response).to have_http_status(:unprocessable_content)
    game.update!(venue_name: 'Changed arena')
    patch path, params: { choice: 'incoming', fingerprint: }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('changed')
    expect(GameScheduleReview.count).to eq(0)
  end

  it 'requires an authenticated admin and a rejection scoped to this run' do
    observation
    sign_out admin
    get path
    expect(response).to redirect_to(new_user_session_path)
    sign_in create(:user)
    get path
    expect(response).to have_http_status(:not_found)
    patch path, params: { choice: 'incoming', fingerprint: 'forged' }
    expect(response).to have_http_status(:not_found)
    sign_in admin
    run.update!(report: {})
    get path
    expect(response).to have_http_status(:not_found)
    expect(GameScheduleReview.count).to eq(0)
  end
end
