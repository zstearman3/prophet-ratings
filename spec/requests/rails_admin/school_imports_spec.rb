# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RailsAdmin school setup from saved standings', type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:season) { create(:season, year: 2027) }
  let!(:conference) { create(:conference, name: 'Test Conference', slug: 'test-conf', abbreviation: 'TEST') }
  let!(:known) { create(:team, school: 'Known U', url: '/cbb/schools/known/men/') }
  let(:path) { "/admin/season/#{season.id}/review_memberships" }
  let(:rows) do
    %w[known new-haven].zip(['Known U', 'New Haven']).map do |slug, name|
      { team_slug: slug, team_name: name, conference_slug: conference.slug,
        conference_name: conference.name, conference_abbreviation: conference.abbreviation }
    end
  end
  let(:scraper) { instance_double(Scraper::ConferenceStandingsScraper, call: rows, source_url: 'https://example.test/standings') }

  before do
    create(:team_alias, team: known, value: known.school)
    create(:team_season, team: known, season:)
    allow(Scraper::ConferenceStandingsScraper).to receive(:new).and_return(scraper)
    SeasonMembershipReview.new(season).refresh
    sign_in create(:user, :admin)
  end

  def source_values
    { proposal_key: SeasonMembershipProposal.digest(season.reload.membership_proposal), team_slug: 'new-haven' }
  end

  def save_values
    source_values.merge(attributes: { school: 'New Haven University', nickname: 'Reviewed nickname', location: 'Reviewed location' })
  end

  it 'previews source defaults from the rendered setup button without fetching or writing records' do
    allow(scraper).to receive(:call).and_raise('School setup must use the saved scrape')
    get path
    form = response.parsed_body.at_css('form.school-setup-form')
    expect(form.text).to include('New Haven')
    expect(form['data-turbo']).to eq('false')
    key = form.at_css('input[name="school_import[proposal_key]"]')['value']
    post form['action'], params: { school_import: { proposal_key: key, team_slug: 'new-haven' } }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.at_css('#school-import-school')['value']).to eq('New Haven')
    expect(Team.count).to eq(1)
    expect(TeamSeason.count).to eq(1)
  end

  it 'saves edited defaults, alias and missing TeamSeason, then allows full membership approval' do
    values = save_values
    post path, params: { operation: 'prepare_school', school_import: source_values }
    form = response.parsed_body.at_css('#school-import-form')
    expect(form['data-turbo']).to eq('false')
    post form['action'], params: { school_import: values }
    expect(response).to redirect_to(path)
    team = Team.find_by!(school: 'New Haven University')
    expect(team).to have_attributes(url: '/cbb/schools/new-haven/men/', nickname: 'Reviewed nickname', location: 'Reviewed location')
    expect(team.team_aliases.find_by!(source: 'sports-reference').value).to eq('New Haven')
    expect(team.team_seasons.pluck(:season_id)).to eq([season.id])
    proposal = season.reload.membership_proposal
    expect(proposal.fetch('issues')).to be_empty
    expect(proposal.fetch('rows').pluck('team_id')).to contain_exactly(known.id, team.id)
    expect(TeamConference.count).to eq(0)
    post path, params: { operation: 'approve', review: {
      proposal_key: SeasonMembershipProposal.digest(proposal),
      teams: [known, team].to_h { |entry| [entry.id.to_s, { choice: conference.id.to_s }] },
      start_date: season.start_date.iso8601, end_date: season.end_date.iso8601
    } }
    expect(response).to redirect_to(path)
    expect(season.reload.participation_review.fetch('teams').pluck('team_id')).to contain_exactly(known.id, team.id)
  end

  it 'finishes an existing manually added school without creating a duplicate or resetting its season values' do
    team = create(:team, school: 'New Haven', url: '/cbb/schools/new-haven/men/', nickname: 'Existing nickname')
    season_row = create(:team_season, team:, season:, adj_pace: 73)
    before = season_row.attributes
    post path, params: { operation: 'prepare_school', school_import: source_values }
    expect(response.parsed_body.at_css('#school-import-nickname')['value']).to eq('Existing nickname')
    post path, params: { operation: 'save_school', school_import: source_values.merge(attributes: { school: team.school }) }
    expect(response).to redirect_to(path)
    expect(Team.count).to eq(2)
    expect(season_row.reload.attributes).to eq(before)
    expect(team.reload.nickname).to eq('Existing nickname')
    expect(team.team_aliases.pluck(:value)).to include('New Haven')
  end

  it 'creates the missing season row for a school added after season preparation' do
    team = create(:team, school: 'New Haven', url: '/cbb/schools/new-haven/men/')
    create(:team_alias, team:, value: team.school)
    post path, params: { operation: 'save_school', school_import: source_values.merge(attributes: { school: team.school }) }
    expect(response).to redirect_to(path)
    expect(team.team_seasons.pluck(:season_id)).to eq([season.id])
    expect(Team.count).to eq(2)
  end

  it 'preserves edited fields on validation errors without partially creating school setup' do
    before = season.reload.membership_proposal
    values = save_values
    values[:attributes][:school] = ''
    post path, params: { operation: 'save_school', school_import: values }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.at_css('#school-import-nickname')['value']).to eq('Reviewed nickname')
    expect(Team.count).to eq(1)
    expect(TeamSeason.count).to eq(1)
    expect(season.reload.membership_proposal).to eq(before)
  end

  it 'rejects source-alias conflicts and rolls back the new team' do
    create(:team_alias, team: known, value: 'New Haven', source: 'sports-reference')
    post path, params: { operation: 'save_school', school_import: save_values }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('conflicts with another team')
    expect(Team.count).to eq(1)
    expect(TeamSeason.count).to eq(1)
  end

  it 'rejects stale or arbitrary source identities without creating a school' do
    post path, params: { operation: 'save_school', school_import: save_values.merge(proposal_key: 'stale') }
    expect(response).to have_http_status(:unprocessable_content)
    post path, params: { operation: 'save_school', school_import: save_values.merge(team_slug: 'invented') }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Team.count).to eq(1)
  end

  it 'preserves prior-year draft provenance and prepares only the target season' do
    SeasonMembershipReview.new(season).refresh(source_year: 2026)
    post path, params: { operation: 'save_school', school_import: save_values }
    expect(response).to redirect_to(path)
    team = Team.find_by!(school: 'New Haven University')
    expect(team.team_seasons.pluck(:season_id)).to eq([season.id])
    proposal = season.reload.membership_proposal
    expect(proposal).to include('source_year' => 2026, 'target_year' => 2027)
    expect(proposal.fetch('rows')).to all(include('carried_forward' => true))
  end

  it 'does not import ambiguous existing identities or replay a completed import' do
    values = save_values
    post path, params: { operation: 'save_school', school_import: values }
    expect(response).to redirect_to(path)
    post path, params: { operation: 'save_school', school_import: values }
    expect(response).to have_http_status(:unprocessable_content)
    create(:team, school: 'Duplicate source identity', url: '/cbb/schools/new-haven/men/')
    SeasonMembershipReview.new(season).refresh
    post path, params: { operation: 'save_school', school_import: save_values }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('no longer awaiting setup')
    expect(Team.count).to eq(3)
    expect(TeamSeason.count).to eq(2)
  end

  it 'keeps preview and save behind the admin login' do
    values = save_values
    sign_out :user
    %w[prepare_school save_school].each do |operation|
      post path, params: { operation:, school_import: values }
      expect(response).to redirect_to('/users/sign_in')
    end
    sign_in create(:user)
    %w[prepare_school save_school].each do |operation|
      post path, params: { operation:, school_import: values }
      expect(response).to redirect_to('/')
    end
    expect(Team.count).to eq(1)
  end
end
