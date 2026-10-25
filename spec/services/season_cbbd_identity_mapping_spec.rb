# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SeasonCbbdIdentityMapping do
  let!(:season) { create(:season, year: 2026) }
  let!(:team) { create(:team, school: 'Example University') }
  let!(:conference) { create(:conference, name: 'Example Conference') }
  let(:source) do
    [{ team_external_id: '001', team_name: team.school, conference_external_id: '10',
       conference_name: conference.name, conference_abbreviation: '' }]
  end

  before do
    create(:team_alias, team:, value: team.school)
    create(:team_season, team:, season:)
    capture_proposal
  end

  def capture_proposal(source_year: season.year)
    proposal = SeasonMembershipProposal.new(season, provider: 'cbbd', source_year:)
                                       .build(source, source_url: 'https://example.test/directory', captured_at: Time.current.iso8601)
    season.update!(membership_proposal: proposal)
  end

  def submission
    { 'proposal_key' => SeasonMembershipProposal.digest(season.reload.membership_proposal),
      'teams' => { '001' => team.id.to_s }, 'conferences' => { '10' => conference.id.to_s } }
  end

  it 'persists reviewed defaults and rebuilds the retained proposal without fetching' do
    before = [team.attributes, conference.attributes, season.team_seasons.sole.attributes]
    described_class.new(season).call(submission)
    expect(TeamExternalIdentity.find_by!(provider: 'cbbd', external_id: '001').team).to eq(team)
    expect(ConferenceExternalIdentity.find_by!(provider: 'cbbd', external_id: '10').conference).to eq(conference)
    expect(season.reload.membership_proposal['issues']).to be_empty
    expect([team.reload.attributes, conference.reload.attributes, season.team_seasons.sole.attributes]).to eq(before)
    expect([TeamConference.count, season.participation_review]).to eq([0, {}])
  end

  it 'lets the operator override both automatic choices before saving' do
    other_team = create(:team)
    other_conference = create(:conference)
    capture_proposal
    attributes = submission
    attributes['teams']['001'] = other_team.id.to_s
    attributes['conferences']['10'] = other_conference.id.to_s
    described_class.new(season).call(attributes)
    expect(TeamExternalIdentity.find_by!(provider: 'cbbd', external_id: '001').team).to eq(other_team)
    expect(ConferenceExternalIdentity.find_by!(provider: 'cbbd', external_id: '10').conference).to eq(other_conference)
    row = season.reload.membership_proposal['rows'].find { |item| item['team_id'] == other_team.id }
    expect(row['choice']).to eq(other_conference.id.to_s)
  end

  it 'rolls back the whole mapping batch when a selected target does not exist' do
    attributes = submission
    attributes['conferences']['10'] = '99999999'
    expect { described_class.new(season).call(attributes) }.to raise_error(ActiveRecord::RecordNotFound)
    expect([TeamExternalIdentity.count, ConferenceExternalIdentity.count]).to eq([0, 0])
  end

  it 'rejects source IDs that are not in the saved directory' do
    attributes = submission
    attributes['teams']['forged'] = team.id.to_s
    expect { described_class.new(season).call(attributes) }.to raise_error(ArgumentError, /source/i)
    expect(TeamExternalIdentity.count).to eq(0)
  end

  it 'rejects changed aliases instead of applying a stale selection' do
    attributes = submission
    create(:team_alias, team:, value: 'New alias', source: 'manual')
    expect { described_class.new(season).call(attributes) }.to raise_error(ArgumentError, /Local roster/)
    expect(TeamExternalIdentity.count).to eq(0)
  end

  it 'saves previous-year identity matches without claiming target-year roster verification' do
    capture_proposal(source_year: 2025)
    described_class.new(season).call(submission)
    expect(TeamExternalIdentity.find_by!(provider: 'cbbd', external_id: '001').team).to eq(team)
    expect(season.reload.membership_proposal).to include('source_year' => 2025, 'target_year' => 2026)
    expect(season.participation_review).to eq({})
  end

  it 'saves a partial batch while leaving blank unknown schools unresolved' do
    source << source.first.merge(team_external_id: '002', team_name: 'Unprepared school')
    capture_proposal
    attributes = submission
    attributes['teams']['002'] = ''
    described_class.new(season).call(attributes)
    expect(TeamExternalIdentity.where(provider: 'cbbd').pluck(:external_id)).to eq(['001'])
    expect(season.reload.membership_proposal['issues'].join).to include('Unprepared school')
    expect(Team.count).to eq(1)
  end

  it 'does not reparent a saved provider identity' do
    TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: '001')
    other = create(:team)
    capture_proposal
    attributes = submission
    attributes['teams']['001'] = other.id.to_s
    expect { described_class.new(season).call(attributes) }.to raise_error(ArgumentError, /saved|mapped/i)
    expect(TeamExternalIdentity.find_by!(provider: 'cbbd', external_id: '001').team).to eq(team)
  end

  it 'rejects two new source school IDs selected for the same local school' do
    source << source.first.merge(team_external_id: '002', team_name: 'Other source label')
    capture_proposal
    attributes = submission
    attributes['teams']['002'] = team.id.to_s
    expect { described_class.new(season).call(attributes) }.to raise_error(ArgumentError, /Multiple source IDs/)
    expect(TeamExternalIdentity.count).to eq(0)
  end
end
