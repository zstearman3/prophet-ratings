# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RailsAdmin season membership review', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:user, :admin) }
  let!(:season) { create(:season, year: 2027) }
  let!(:team) { create(:team, school: 'Example U', url: '/cbb/schools/example/men/') }
  let!(:conference) { create(:conference, name: 'Big 12', slug: 'big-12', abbreviation: 'B12') }
  let(:path) { "/admin/season/#{season.id}/review_memberships" }
  let(:rows) do
    [{ team_slug: 'example', team_name: team.school, conference_slug: conference.slug,
       conference_name: conference.name, conference_abbreviation: conference.abbreviation }]
  end
  let(:scraper) do
    instance_double(Scraper::ConferenceStandingsScraper, call: rows,
                                                         source_url: 'https://www.sports-reference.com/cbb/seasons/men/2027-standings.html')
  end

  before do
    SeasonPreparer.new(year: season.year).call
    create(:team_alias, team:, value: team.school)
    allow(Scraper::ConferenceStandingsScraper).to receive(:new).and_return(scraper)
  end

  it 'protects viewing and mutation with the admin login' do
    get path
    expect(response).to redirect_to('/users/sign_in')
    post path, params: { operation: 'refresh' }
    expect(response).to redirect_to('/users/sign_in')
    sign_in create(:user)
    get path
    expect(response).to redirect_to('/')
    post path, params: { operation: 'refresh' }
    expect(response).to redirect_to('/')
    expect(scraper).not_to have_received(:call)
    expect(season.reload.membership_proposal).to eq({})
  end

  context 'with an admin' do
    before { sign_in admin }

    it 'links the season to the review and does not fetch data on GET' do
      get "/admin/season/#{season.id}"
      expect(response.body).to include('Review memberships')
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Fetch proposals from Sports Reference')
      expect(scraper).not_to have_received(:call)
    end

    it 'renders source proposals as a school/year table without changing membership' do
      post path, params: { operation: 'refresh' }
      expect(response).to redirect_to(path)
      follow_redirect!
      expect(response.body).to include('Example U', '2026 Membership', '2027 Proposed Membership', 'Big 12', 'not in D1')
      expect(TeamConference.count).to eq(0)
      expect(season.reload.participation_review).to eq({})
    end

    it 'approves the complete review through the form and records the signed-in reviewer' do
      post path, params: { operation: 'refresh' }
      season.reload
      post path, params: { operation: 'approve', review: {
        proposal_key: SeasonMembershipReview.new(season).proposal_key,
        teams: { team.id.to_s => { choice: conference.id.to_s } },
        start_date: '2026-11-01', end_date: '2027-04-10', evidence: 'Official roster and schedule reviewed'
      } }
      expect(response).to redirect_to(path)
      follow_redirect!
      expect(response.body).to include('Stored participation review', admin.email)
      expect(team.conference_for(season)).to eq(conference)
      expect(season.reload.participation_review.fetch('reviewed_by')).to eq(admin.email)
      expect(season).not_to be_current
    end

    it 'renders actionable errors and preserves entered decisions for correction' do
      post path, params: { operation: 'refresh' }
      season.reload
      post path, params: { operation: 'approve', review: {
        proposal_key: SeasonMembershipReview.new(season).proposal_key,
        teams: { team.id.to_s => { choice: 'excluded', reason: 'Pending verification' } },
        start_date: '2026-11-01', end_date: '2027-04-10', evidence: ''
      } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Provide roster/date evidence', 'Pending verification')
      expect(season.reload.participation_review).to eq({})
    end

    it 'preserves a proposal after scraper failures' do
      post path, params: { operation: 'refresh' }
      original = season.reload.membership_proposal
      allow(scraper).to receive(:call).and_raise(Scraper::ConferenceStandingsScraper::Error, 'HTTP 403')
      post path, params: { operation: 'refresh' }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('HTTP 403', 'Example U')
      expect(season.reload.membership_proposal).to eq(original)
    end
  end
end
