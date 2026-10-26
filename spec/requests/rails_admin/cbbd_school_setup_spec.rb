# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Inline CBBD school setup', type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:season) { create(:season, year: 2027) }
  let!(:conference) { create(:conference, name: 'Synthetic Conference') }
  let(:path) { "/admin/season/#{season.id}/review_memberships" }
  let(:source) do
    { 'provider' => 'cbbd', 'source_url' => 'https://example.test/directory?season=2027',
      'captured_at' => '2026-10-26T12:00:00Z', 'acquisition' => { 'version' => 1, 'captures' => [{ 'id' => 'retained' }] },
      'source_rows' => [{ team_external_id: '001', team_name: 'Synthetic U', conference_external_id: '10',
                          conference_name: conference.name, conference_abbreviation: 'SC' }] }
  end

  around do |example|
    previous = ENV.to_h
    ENV['GAME_SYNC_PROVIDER'] = 'cbbd'
    example.run
  ensure
    ENV.replace(previous)
  end

  before do
    sign_in create(:user, :admin)
    allow(Ingestion::Cbbd::MembershipDirectory).to receive(:new).and_return(double(call: source))
    allow(Scraper::ConferenceStandingsScraper).to receive(:new).and_raise('Unexpected SR request')
  end

  def refresh
    post path, params: { operation: 'refresh' }
    expect(response).to redirect_to(path)
    season.reload
  end

  def submission(attributes = {})
    { team_external_id: '001', proposal_key: SeasonMembershipProposal.digest(season.reload.membership_proposal),
      attributes: { school: 'Reviewed University', url: '/cbb/schools/reviewed/men/', nickname: 'Reviewers' }.merge(attributes) }
  end

  def save_school(values = submission)
    post path, params: { operation: 'save_school', school_import: values }
  end

  it 'opens an inline form from the rendered setup action without changing records' do
    refresh
    get path
    form = response.parsed_body.at_css('form.school-setup-form')
    expect(form).to be_present
    values = form.css('input[name]').to_h { |input| [input['name'], input['value']] }
    post form['action'], params: Rack::Utils.parse_nested_query(URI.encode_www_form(values))
    expect(response).to have_http_status(:ok)
    form = response.parsed_body.at_css('#cbbd-school-setup-form')
    expect(form.at_css('[name="school_import[attributes][school]"]')['value']).to eq('Synthetic U')
    expect(form.at_css('[name="school_import[attributes][url]"]')['required']).to be_present
    expect(form.css('[name*="reason"], [name*="evidence"]')).to be_empty
    expect([Team.count, TeamAlias.count, TeamSeason.count, TeamExternalIdentity.count]).to eq([0, 0, 0, 0])
  end

  it 'creates all school dependencies and rebuilds the proposal from retained evidence' do
    refresh
    save_school(submission(url: 'https://www.sports-reference.com/cbb/schools/reviewed/men/'))
    expect(response).to redirect_to(path)
    team = Team.find_by!(school: 'Reviewed University')
    expect(team.attributes).to include('url' => '/cbb/schools/reviewed/men/', 'nickname' => 'Reviewers', 'location' => nil)
    expect(team.team_aliases.sole.attributes).to include('value' => 'Synthetic U', 'source' => 'cbbd')
    expect(team.team_seasons.sole.season).to eq(season)
    expect(TeamExternalIdentity.find_by!(provider: 'cbbd', external_id: '001').team).to eq(team)
    proposal = season.reload.membership_proposal
    expect(proposal['acquisition']).to eq(source['acquisition'])
    expect(proposal['rows'].sole).to include('team_id' => team.id, 'choice' => conference.id.to_s)
    expect(proposal['issues']).to be_empty
    expect([TeamConference.count, season.participation_review, TeamRatingSnapshot.count]).to eq([0, {}, 0])
  end

  it 'finishes a matched school without duplicating it or creating another season record' do
    team = create(:team, school: 'Synthetic U', url: '/cbb/schools/synthetic/men/', nickname: 'Known')
    create(:team_season, team:, season:)
    refresh
    post path, params: { operation: 'prepare_school', school_import: submission }
    expect(response.parsed_body.at_css('[name="school_import[attributes][url]"]')['value']).to eq(team.url)
    save_school(submission(school: team.school, url: team.url, nickname: 'Known'))
    expect(response).to redirect_to(path)
    expect([Team.count, TeamSeason.count]).to eq([1, 1])
    expect(team.reload.nickname).to eq('Known')
    expect(team.team_aliases.sole.value).to eq('Synthetic U')
    expect(TeamExternalIdentity.find_by!(provider: 'cbbd', external_id: '001').team).to eq(team)
  end

  it 'retains entered metadata after invalid input and performs no partial setup' do
    refresh
    save_school(submission(url: '', location: 'Verified location'))
    expect(response).to have_http_status(:unprocessable_content)
    form = response.parsed_body.at_css('#cbbd-school-setup-form')
    expect(form.at_css('[name="school_import[attributes][school]"]')['value']).to eq('Reviewed University')
    expect(form.at_css('[name="school_import[attributes][location]"]')['value']).to eq('Verified location')
    expect([Team.count, TeamAlias.count, TeamSeason.count, TeamExternalIdentity.count]).to eq([0, 0, 0, 0])
  end

  it 'rejects unrelated URLs rather than storing invalid legacy school identifiers' do
    refresh
    original = season.membership_proposal
    ['https://example.test/cbb/schools/reviewed/men/', '//example.test/cbb/schools/reviewed/men/',
     'javascript:alert(1)', '/cbb/schools/reviewed/men/?query=1'].each do |url|
      save_school(submission(url:))
      expect(response).to have_http_status(:unprocessable_content)
      expect(season.reload.membership_proposal).to eq(original)
    end
    expect([Team.count, TeamAlias.count, TeamSeason.count, TeamExternalIdentity.count]).to eq([0, 0, 0, 0])
  end

  it 'rejects stale and unknown source submissions without creating records' do
    refresh
    valid = submission
    [valid.merge(proposal_key: 'stale'), valid.merge(team_external_id: 'unknown')].each do |values|
      save_school(values)
      expect(response).to have_http_status(:unprocessable_content)
    end
    expect([Team.count, TeamAlias.count, TeamSeason.count, TeamExternalIdentity.count]).to eq([0, 0, 0, 0])
  end

  it 'rejects a new name that already identifies a different local school' do
    team = create(:team, school: 'Existing U', url: '/cbb/schools/existing/men/')
    create(:team_alias, team:, value: 'Reviewed University')
    refresh
    original = team.attributes
    save_school
    expect(response).to have_http_status(:unprocessable_content)
    expect(team.reload.attributes).to eq(original)
    expect([Team.count, TeamSeason.count, TeamExternalIdentity.count]).to eq([1, 0, 0])
  end

  it 'rolls back school edits and dependencies when two provider IDs would share a school' do
    team = create(:team, school: 'Synthetic U', url: '/cbb/schools/synthetic/men/', nickname: 'Known')
    TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: '002')
    source['source_rows'] << source['source_rows'].sole.merge(team_external_id: '002', team_name: 'Other source name')
    refresh
    original = team.attributes
    save_school(submission(school: team.school, url: team.url, nickname: 'Changed'))
    expect(response).to have_http_status(:unprocessable_content)
    expect(team.reload.attributes).to eq(original)
    expect([TeamAlias.count, TeamSeason.count, TeamExternalIdentity.count]).to eq([0, 0, 1])
    expect(TeamExternalIdentity.sole.external_id).to eq('002')
  end

  it 'sets up two missing schools in sequence without another provider fetch' do
    source['source_rows'] << source['source_rows'].sole.merge(team_external_id: '002', team_name: 'Second U')
    refresh
    allow(Ingestion::Cbbd::MembershipDirectory).to receive(:new).and_raise('Unexpected CBBD fetch')
    save_school
    expect(response).to redirect_to(path)
    save_school(submission(school: 'Second U', url: '/cbb/schools/second/men/').merge(team_external_id: '002'))
    expect(response).to redirect_to(path)
    expect(Team.order(:school).pluck(:school)).to eq(['Reviewed University', 'Second U'])
    expect([TeamAlias.count, TeamSeason.count, TeamExternalIdentity.count]).to eq([2, 2, 2])
    expect(season.reload.membership_proposal['issues']).to be_empty
    expect(season.participation_review).to eq({})
  end

  it 'requires admin authentication for school setup' do
    refresh
    values = submission
    sign_out :user
    save_school(values)
    expect(response).to redirect_to('/users/sign_in')
    expect(Team.count).to eq(0)
  end
end
