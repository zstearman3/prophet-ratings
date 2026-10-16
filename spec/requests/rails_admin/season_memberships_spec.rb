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
    %w[refresh refresh_previous correct_memberships].each do |operation|
      post path, params: { operation: }
      expect(response).to redirect_to('/users/sign_in')
    end
    sign_in create(:user)
    get path
    expect(response).to redirect_to('/')
    %w[refresh refresh_previous correct_memberships].each do |operation|
      post path, params: { operation: }
      expect(response).to redirect_to('/')
    end
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
        teams: { team.id.to_s => { choice: 'unresolved' } },
        start_date: '2026-11-01', end_date: '2027-04-10', evidence: ''
      } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('choose a membership or explicitly exclude the school.')
      expect(season.reload.participation_review).to eq({})
    end

    it 'fetches and displays proposals for an established season while hiding full approval and date inputs' do
      season.update!(current: true)
      post path, params: { operation: 'refresh' }
      expect(response).to redirect_to(path)
      follow_redirect!
      expect(response.body).to include('established outputs', 'Example U', 'Apply selected conference corrections only')
      expect(response.body).not_to include('Approve memberships, participation and dates', 'review[start_date]')
      expect(season.reload).to be_current
      expect(season.participation_review).to eq({})
    end

    it 'keeps full approval guarded even when it is posted directly for an established season' do
      season.update!(current: true)
      post path, params: { operation: 'refresh' }
      post path, params: { operation: 'approve', review: { proposal_key: SeasonMembershipReview.new(season.reload).proposal_key } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('existing season outputs must be preserved')
      expect(season.reload.participation_review).to eq({})
    end

    it 'offers a separately selected previous-season draft with source/target years and verification confirmation' do
      prior = instance_double(Scraper::ConferenceStandingsScraper, call: rows,
                                                                   source_url: 'https://www.sports-reference.com/cbb/seasons/men/2026-standings.html')
      allow(Scraper::ConferenceStandingsScraper).to receive(:new).with(year: 2026).and_return(prior)
      post path, params: { operation: 'refresh_previous' }
      expect(response).to redirect_to(path)
      follow_redirect!
      expect(response.body).to include('Target 2027 proposal based on 2026 memberships', 'Carried forward', 'review[confirm_target_year]')
      expect(season.reload.membership_proposal).to include('source_year' => 2026, 'target_year' => 2027)
      expect(TeamConference.count).to eq(0)
    end

    it 'applies selected conference-only corrections without accepting submitted date or roster changes' do
      previous = create(:season, year: 2026)
      following = create(:season, year: 2028)
      old = create(:conference, name: 'SEC')
      create(:team_conference, team:, conference: old, start_season: previous)
      season.update!(current: true)
      before = season.attributes.slice('start_date', 'end_date', 'participation_review')
      post path, params: { operation: 'refresh' }
      post path, params: { operation: 'correct_memberships', review: {
        proposal_key: SeasonMembershipReview.new(season.reload).proposal_key,
        teams: { team.id.to_s => { selected: '1', choice: conference.id.to_s } },
        confirm_memberships_only: '1', evidence: 'Official conference records reviewed',
        start_date: '2000-01-01', end_date: '2000-02-01', participation_review: { teams: [] }
      } }
      expect(response).to redirect_to(path)
      follow_redirect!
      expect(response.body).to include('Last conference-only correction', admin.email)
      expect([previous, season, following].map { |year| team.conference_for(year) }).to eq([old, conference, old])
      expect(season.reload.attributes.slice('start_date', 'end_date', 'participation_review')).to eq(before)
      expect(season.membership_corrections.sole.fetch('reviewed_by')).to eq(admin.email)
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
