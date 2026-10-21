# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RailsAdmin conference source mappings', type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:season) { create(:season, year: 2027, current: true) }
  let!(:conference) { create(:conference, name: 'American Athletic Conference', slug: 'aac', abbreviation: 'AAC') }
  let!(:teams) { %w[first second].map { |slug| create(:team, school: slug.titleize, url: "/cbb/schools/#{slug}/men/") } }
  let(:path) { "/admin/season/#{season.id}/review_memberships" }
  let(:source_url) { 'https://example.test/standings' }
  let(:rows) do
    teams.map do |team|
      { team_slug: ConferenceAlignmentMatch.source_slug(team), team_name: team.school,
        conference_slug: 'american', conference_name: 'American Conference', conference_abbreviation: 'AMER' }
    end
  end
  let(:scraper) { instance_double(Scraper::ConferenceStandingsScraper, call: rows, source_url:) }

  before do
    allow(Scraper::ConferenceStandingsScraper).to receive(:new).and_return(scraper)
    SeasonMembershipReview.new(season).refresh
    sign_in create(:user, :admin)
  end

  def mapping_values(conferences = { 'american' => conference.id.to_s })
    { proposal_key: SeasonMembershipProposal.digest(season.reload.membership_proposal), conferences: }
  end

  it 'groups unmatched source conferences with school counts and posts through the rendered form URL' do
    get path
    form = response.parsed_body.at_css('#conference-mapping-form')
    expect(form.css('tbody tr').size).to eq(1)
    expect(form.text).to include('American Conference', 'american', '2')
    expect(season.membership_proposal.fetch('issues').size).to eq(1)
    expect(season.membership_proposal.fetch('issues').sole).to include('(2 schools)')
    expect(form['data-turbo']).to eq('false')
    post form['action'], params: { mapping: mapping_values }
    expect(response).to redirect_to(path)
    follow_redirect!
    expect(response.parsed_body.at_css('#conference-mapping-form')).to be_nil
  end

  it 'saves an alias and rebuilds from saved rows without fetching or changing memberships or season outputs' do
    original = season.reload.attributes
    allow(scraper).to receive(:call).and_raise('Mapping must not fetch')
    post path, params: { operation: 'map_conferences', mapping: mapping_values }
    expect(response).to redirect_to(path)
    expect(conference.reload.sports_reference_slugs).to eq(['american'])
    expect(conference.slug).to eq('aac')
    proposal = season.reload.membership_proposal
    expect(proposal.values_at('source_url', 'captured_at', 'source_rows')).to eq(
      original.fetch('membership_proposal').values_at('source_url', 'captured_at', 'source_rows')
    )
    expect(proposal.fetch('rows').pluck('choice')).to eq([conference.id.to_s, conference.id.to_s])
    expect(proposal.fetch('issues')).to be_empty
    expect(proposal.fetch('fingerprint')).to eq(SeasonMembershipProposal.new(season).fingerprint)
    expect(season.attributes.except('membership_proposal', 'updated_at')).to eq(original.except('membership_proposal', 'updated_at'))
    expect(TeamConference.count).to eq(0)
    expect(ConferenceAlignmentMatch.resolve(rows).map(&:conference)).to eq([conference, conference])
  end

  it 'preserves source and target years when rebuilding a previous-season draft' do
    SeasonMembershipReview.new(season).refresh(source_year: 2026)
    post path, params: { operation: 'map_conferences', mapping: mapping_values }
    expect(response).to redirect_to(path)
    proposal = season.reload.membership_proposal
    expect(proposal).to include('source_year' => 2026, 'target_year' => 2027)
    expect(proposal.fetch('rows')).to all(include('carried_forward' => true))
  end

  it 'rejects stale proposal keys and slugs outside the saved unmatched source' do
    post path, params: { operation: 'map_conferences', mapping: mapping_values.merge(proposal_key: 'stale') }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Proposal changed')
    post path, params: { operation: 'map_conferences', mapping: mapping_values('invented' => conference.id.to_s) }
    expect(response).to have_http_status(:unprocessable_content)
    expect(conference.reload.sports_reference_slugs).to be_empty
  end

  it 'does not reassign a source slug claimed since discovery' do
    other = create(:conference, sports_reference_slugs: ['american'])
    post path, params: { operation: 'map_conferences', mapping: mapping_values }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Local roster')
    expect(other.reload.sports_reference_slugs).to eq(['american'])
    expect(conference.reload.sports_reference_slugs).to be_empty
  end

  it 'rolls back all aliases and the proposal if a later mapping fails' do
    rows.last.merge!(conference_slug: 'atlantic-sun', conference_name: 'Atlantic Sun Conference', conference_abbreviation: 'ASUN')
    SeasonMembershipReview.new(season).refresh
    before = season.reload.membership_proposal
    post path, params: { operation: 'map_conferences', mapping: mapping_values(
      'american' => conference.id.to_s, 'atlantic-sun' => '999999999'
    ) }
    expect(response).to have_http_status(:unprocessable_content)
    expect(conference.reload.sports_reference_slugs).to be_empty
    expect(season.reload.membership_proposal).to eq(before)
  end

  it 'keeps mapping writes behind the admin login' do
    values = mapping_values
    sign_out :user
    post path, params: { operation: 'map_conferences', mapping: values }
    expect(response).to redirect_to('/users/sign_in')
    sign_in create(:user)
    post path, params: { operation: 'map_conferences', mapping: values }
    expect(response).to redirect_to('/')
    expect(conference.reload.sports_reference_slugs).to be_empty
  end
end
