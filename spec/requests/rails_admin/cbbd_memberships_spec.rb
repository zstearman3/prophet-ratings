# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RailsAdmin CBBD membership preparation', type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:season) { create(:season, year: 2027) }
  let!(:conference) { create(:conference) }
  let(:path) { "/admin/season/#{season.id}/review_memberships" }
  let(:source) do
    { 'provider' => 'cbbd', 'source_url' => 'https://api.collegebasketballdata.com/teams/directory?season=2027',
      'captured_at' => '2026-10-21T12:00:00Z', 'acquisition' => { 'version' => 1, 'captures' => [] },
      'source_rows' => [{ team_external_id: '001', team_name: 'Synthetic U', conference_external_id: '10',
                          conference_name: 'Synthetic Conference', conference_abbreviation: 'SC' }] }
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

  def proposal_key
    SeasonMembershipProposal.digest(season.reload.membership_proposal)
  end

  def setup_school
    team = create(:team, school: 'Manually verified school', url: '/cbb/schools/user-supplied/men/')
    create(:team_alias, team:, value: 'Synthetic U')
    create(:team_season, team:, season:)
    TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: '001')
    team
  end

  it 'preselects exact aliases and conferences and saves an operator override without approving the roster' do
    team = create(:team, school: 'Canonical U')
    create(:team_alias, team:, value: 'Synthetic U', source: 'manual')
    create(:team_season, team:, season:)
    conference.update!(name: 'Synthetic Conference')
    override = create(:conference)
    refresh
    get path
    school_select = response.parsed_body.at_css('select[name="mapping[teams][001]"]')
    conference_select = response.parsed_body.at_css('select[name="mapping[conferences][10]"]')
    expect(school_select&.at_css('option[selected]')&.[]('value')).to eq(team.id.to_s)
    expect(conference_select&.at_css('option[selected]')&.[]('value')).to eq(conference.id.to_s)
    expect([TeamExternalIdentity.count, ConferenceExternalIdentity.count]).to eq([0, 0])
    post path, params: { operation: 'map_cbbd_identities', mapping: { proposal_key:, teams: { '001' => team.id },
                                                                      conferences: { '10' => override.id } } }
    expect(response).to redirect_to(path)
    expect(TeamExternalIdentity.find_by!(provider: 'cbbd', external_id: '001').team).to eq(team)
    expect(ConferenceExternalIdentity.find_by!(provider: 'cbbd', external_id: '10').conference).to eq(override)
    expect(season.reload.membership_proposal['rows'].sole['choice']).to eq(override.id.to_s)
    expect([TeamConference.count, season.participation_review]).to eq([0, {}])
  end

  it 'requires saving proposed identities before full roster approval' do
    team = create(:team, school: 'Synthetic U')
    create(:team_alias, team:, value: team.school)
    create(:team_season, team:, season:)
    conference.update!(name: 'Synthetic Conference')
    refresh
    post path, params: { operation: 'approve', review: { proposal_key:, start_date: season.start_date.iso8601,
                                                         end_date: season.end_date.iso8601, confirm_source_coverage: '1',
                                                         teams: { team.id => { choice: conference.id } } } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Save CBBD identity matches')
    expect(season.reload.participation_review).to eq({})
  end

  it 'shares override choices instead of repeating every school option for every exact match' do
    team = create(:team, school: 'Synthetic U')
    others = create_list(:team, 3)
    create(:team_alias, team:, value: team.school)
    create(:team_season, team:, season:)
    conference.update!(name: 'Synthetic Conference')
    refresh
    get path
    select = response.parsed_body.at_css('select[name="mapping[teams][001]"]')
    expect(select.css('option').size).to eq(2)
    expect(select.at_css('option[selected]')['value']).to eq(team.id.to_s)
    choices = response.parsed_body.at_css('template#cbbd-teams-options')
    expect(choices.css('option').pluck('value')).to include(*others.map { |other| other.id.to_s })
  end

  it 'approves a roster after accepting the preselected identity matches' do
    team = create(:team, school: 'Synthetic U')
    create(:team_alias, team:, value: team.school)
    create(:team_season, team:, season:)
    conference.update!(name: 'Synthetic Conference')
    refresh
    post path, params: { operation: 'map_cbbd_identities', mapping: { proposal_key:, teams: { '001' => team.id },
                                                                      conferences: { '10' => conference.id } } }
    expect(response).to redirect_to(path)
    get path
    expect(response.parsed_body.at_css('#cbbd-identity-mapping-form')).to be_nil
    review = { proposal_key:, start_date: season.start_date.iso8601, end_date: season.end_date.iso8601,
               confirm_source_coverage: '1', teams: { team.id => { choice: conference.id } } }
    post path, params: { operation: 'approve', review: }
    expect(response).to redirect_to(path)
    expect(team.conference_for(season)).to eq(conference)
    expect(season.reload.participation_review['teams']).to include(hash_including('team_id' => team.id, 'status' => 'included'))
  end

  it 'supports explicit manual school setup, retained conference mapping and reviewed approval without SR' do
    refresh
    get path
    expect(response.body).to include('CBBD schools needing setup', '001', 'do not prove complete')
    expect(response.parsed_body.at_css('.school-setup-form')).to be_present
    team = setup_school
    refresh
    ENV['GAME_SYNC_PROVIDER'] = 'sports_reference'
    post path, params: { operation: 'map_conferences', mapping: { proposal_key:, conferences: { '10' => conference.id } } }
    expect(response).to redirect_to(path)
    expect(conference.reload.sports_reference_slugs).to be_empty
    expect(season.reload.membership_proposal).to include('provider' => 'cbbd', 'acquisition' => source['acquisition'])
    review = { proposal_key:, start_date: season.start_date.iso8601, end_date: season.end_date.iso8601,
               teams: { team.id => { choice: conference.id } } }
    post path, params: { operation: 'approve', review: }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('source coverage')
    expect(TeamConference.count).to eq(0)
    post path, params: { operation: 'approve', review: review.merge(confirm_source_coverage: '1') }
    expect(response).to redirect_to(path)
    expect(team.conference_for(season)).to eq(conference)
    expect(team.team_conferences.sole.end_season).to be_nil
    expect(season.reload.participation_review['source_coverage_confirmed']).to be(true)
  end

  it 'guards direct school import submissions, authentication and stale keys' do
    refresh
    %w[prepare_school save_school].each do |operation|
      post path, params: { operation:, school_import: { proposal_key:, team_slug: 'forged' } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('School is no longer awaiting setup')
    end
    post path, params: { operation: 'map_conferences', mapping: { proposal_key: 'stale', conferences: { '10' => conference.id } } }
    expect(response).to have_http_status(:unprocessable_content)
    sign_out :user
    post path, params: { operation: 'refresh' }
    expect(response).to redirect_to('/users/sign_in')
    expect(Team.count).to eq(0)
    expect(ConferenceExternalIdentity.count).to eq(0)
  end

  it 'keeps GET read-only without credentials and failed acquisitions preserve the prior draft' do
    refresh
    original = season.attributes
    ENV.delete('CBBD_API_KEY')
    allow(Ingestion::Cbbd::MembershipDirectory).to receive(:new).and_raise(ArgumentError,
                                                                           'CBBD directory acquisition failed: authentication')
    get path
    expect(response).to have_http_status(:ok)
    expect(season.reload.attributes).to eq(original)
    post path, params: { operation: 'refresh' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(season.reload.attributes).to eq(original)
  end

  it 'preserves established stored outputs and participation across fetch, mapping and selected correction' do
    team = setup_school
    season.update!(current: true, participation_review: { 'evidence' => 'Prior approved roster' })
    previous = create(:season, year: 2026)
    following = create(:season, year: 2028)
    old = create(:conference)
    create(:team_conference, team:, conference: old, start_season: previous)
    row = TeamSeason.find_by!(team:, season:)
    version = create(:ratings_config_version)
    snapshot = create(:team_rating_snapshot, team_season: row, ratings_config_version: version)
    game = create(:game, season:, in_conference: true)
    box = create(:team_game, game:, team:, team_season: row)
    prediction = create(:prediction, game:, home_team_snapshot: snapshot, away_team_snapshot: snapshot, ratings_config_version: version)
    records = [team, row, snapshot, game, box, prediction, old, conference, previous, following]
    before = records.map(&:attributes)
    approved = season.attributes.slice('participation_review', 'start_date', 'end_date', 'current')
    refresh
    post path, params: { operation: 'map_conferences', mapping: { proposal_key:, conferences: { '10' => conference.id } } }
    expect(response).to redirect_to(path)
    post path, params: { operation: 'approve', review: { proposal_key: } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('existing season outputs must be preserved')
    post path, params: { operation: 'correct_memberships', review: { proposal_key:, confirm_memberships_only: '1',
                                                                     teams: { team.id => { selected: '1', choice: conference.id } } } }
    expect(response).to redirect_to(path)
    expect(records.map { |record| record.reload.attributes }).to eq(before)
    expect(season.reload.attributes.slice('participation_review', 'start_date', 'end_date', 'current')).to eq(approved)
    expect([previous, season, following].map { |year| team.conference_for(year) }).to eq([old, conference, old])
    audit = season.membership_corrections.sole
    expect(audit['source']).to include('provider' => 'cbbd', 'acquisition' => source['acquisition'])
  end
end
