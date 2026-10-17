# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin coaching review workflow', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:path) { '/admin/coaching_reviews/2027' }
  let(:team) { create(:team, school: 'Review University') }
  let(:candidate) { CoachingChange.create!(effective_year: 2027, team:, coach_name: 'Incoming Coach') }

  before { sign_in create(:user, :admin) }

  def review_values
    get path
    { review_key: response.parsed_body.at_css('input[name="review[review_key]"]')['value'], confirm: '1' }
  end

  it 'links seasons and the coaching admin to the yearly review without requiring a season for discovery' do
    get '/admin/coaching_reviews', params: { year: 2027 }
    expect(response).to redirect_to(path)
    get '/admin/coaching_change/coaching_review_queue'
    expect(response).to redirect_to('/admin/coaching_reviews')
    season = create(:season, year: 2027)
    get "/admin/season/#{season.id}/review_coaching"
    expect(response).to redirect_to(path)
    get path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Fetch coaching changes', 'Save and mark year ready', 'Add a manual coaching candidate')
  end

  it 'queues discovery and makes background status visible without running the scraper in the request' do
    allow(DiscoverCoachingChangesJob).to receive(:perform_later)
    post "#{path}/discover"
    record = CoachingReview.find_by!(year: 2027)
    expect(record.discovery_status).to eq('queued')
    expect(DiscoverCoachingChangesJob).to have_received(:perform_later).with(record.id)
    follow_redirect!
    expect(response.body).to include('background worker', 'Refresh status')
    expect(Season.count).to eq(0)
  end

  it 'adds a manual candidate, edits facts and marks the year ready from the same form' do
    team
    post "#{path}/candidate"
    record = CoachingChange.sole
    values = review_values.merge(rows: { record.id => { team_id: team.id, coach_name: 'Reviewed Coach', status: 'confirmed' } })
    patch path, params: { review: values, intent: 'ready' }
    expect(response).to redirect_to(path)
    expect(record.reload).to have_attributes(team_id: team.id, coach_name: 'Reviewed Coach', status: 'confirmed')
    expect(CoachingReview.find_by!(year: 2027)).to be_ready
    expect([TeamSeason.count, TeamOffseasonProfile.count, TeamRatingSnapshot.count, PreseasonPrior.count]).to eq([0, 0, 0, 0])
  end

  it 'preserves submitted choices and shows actionable history errors without saving partial changes' do
    candidate
    values = review_values.merge(rows: { candidate.id => { coach_name: 'Edited Coach', status: 'confirmed', full_season_head_coach: '1' } })
    patch path, params: { review: values, intent: 'ready' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Previous team', 'Previous year')
    expect(response.parsed_body.at_css("input[name='review[rows][#{candidate.id}][coach_name]']")['value']).to eq('Edited Coach')
    expect(candidate.reload.coach_name).to eq('Incoming Coach')
    expect(CoachingReview.count).to eq(0)
  end

  it 'requires explicit confirmation and rejects stale forms' do
    candidate
    values = review_values
    patch path, params: { review: values.merge(confirm: '0'), intent: 'save' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Confirm that you reviewed')
    candidate.update!(coach_name: 'Concurrent edit')
    patch path, params: { review: values, intent: 'ready' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('reload and review again')
  end

  it 'paginates candidates and checks readiness across every page' do
    26.times { CoachingChange.create!(effective_year: 2027) }
    get path
    expect(response.body).to include('Page 1 of 2')
    expect(response.parsed_body.css('select').count).to eq(100)
    records = CoachingChange.order(:id).limit(25)
    values = review_values.merge(rows: records.to_h { |record| [record.id, { status: 'rejected' }] })
    patch path, params: { review: values, intent: 'ready' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('every pending')
    expect(CoachingChange.where(status: 'rejected').count).to eq(0)
    patch path, params: { review: values, intent: 'save', page: 1 }
    expect(response).to redirect_to("#{path}?page=1")
    expect(CoachingChange.where(status: 'pending').count).to eq(1)
  end

  it 'shows failed fetches and source conflicts from stored records' do
    CoachingReview.create!(year: 2027, discovery_status: 'failed', discovery_error: 'Source HTTP 403')
    candidate.update!(status: 'confirmed', discovery_school: 'review university', discovery_present: false,
                      discovery_coach_name: 'Source Coach', discovery_former_coach: 'Former Coach')
    get path
    expect(response.body).to include('Source HTTP 403', 'Source Coach', 'Former Coach',
                                     'Absent from latest successful source fetch', 'Source incoming coach differs')
  end

  it 'requires admin login for every screen and mutation' do
    sign_out :user
    requests = [[:get, '/admin/coaching_reviews'], [:get, path], [:patch, path], [:post, "#{path}/discover"], [:post, "#{path}/candidate"]]
    requests.each do |verb, url|
      public_send(verb, url)
      expect(response).to redirect_to('/users/sign_in')
    end
    sign_in create(:user)
    requests.each do |verb, url|
      public_send(verb, url)
      expect(response).to redirect_to('/')
    end
    expect(CoachingReview.count).to eq(0)
    expect(CoachingChange.count).to eq(0)
  end
end
