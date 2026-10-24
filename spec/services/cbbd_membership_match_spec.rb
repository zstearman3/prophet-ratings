# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CbbdMembershipMatch do
  let!(:team) { create(:team, school: 'Example University') }
  let!(:conference) { create(:conference, name: 'Example Conference', abbreviation: 'EC') }
  let(:row) do
    { team_external_id: '001', team_name: 'Example University', conference_external_id: '10',
      conference_name: 'Example Conference', conference_abbreviation: 'EC' }
  end

  def match
    described_class.resolve([row]).sole
  end

  it 'defaults unique exact school and conference names without persisting identities' do
    row.merge!(team_name: ' example UNIVERSITY ', conference_name: ' EXAMPLE conference ')
    expect([match.team, match.conference, match.suggestions]).to eq([team, conference, []])
    expect([TeamExternalIdentity.count, ConferenceExternalIdentity.count]).to eq([0, 0])
  end

  it 'matches any existing school alias regardless of alias source' do
    create(:team_alias, team:, value: 'Alternate U', source: 'manual')
    row[:team_name] = ' alternate u '
    expect(match.team).to eq(team)
  end

  it 'matches an exact conference abbreviation when the name differs' do
    row[:conference_name] = 'Different source label'
    expect(match.conference).to eq(conference)
  end

  it 'keeps saved provider mappings authoritative over matching display names' do
    other_team = create(:team)
    other_conference = create(:conference)
    TeamExternalIdentity.associate!(team: other_team, provider: 'cbbd', external_id: '001')
    ConferenceExternalIdentity.associate!(conference: other_conference, provider: 'cbbd', external_id: '10')
    expect([match.team, match.conference]).to eq([other_team, other_conference])
  end

  it 'holds a canonical name that also aliases a different school' do
    other = create(:team)
    create(:team_alias, team: other, value: team.school)
    expect(match.team).to be_nil
    expect(match.suggestions.join).to include('Ambiguous CBBD school')
  end

  it 'holds conflicting exact conference name and abbreviation candidates' do
    create(:conference, abbreviation: 'EC')
    expect(match.conference).to be_nil
    expect(match.suggestions.join).to include('Ambiguous CBBD conference')
  end

  it 'does not match blank conference abbreviations or similar school names' do
    row.merge!(team_name: 'Example Univ', conference_name: 'Example Conf', conference_abbreviation: '')
    expect([match.team, match.conference]).to eq([nil, nil])
  end

  it 'holds different source school IDs resolving to the same local school' do
    rows = [row, row.merge(team_external_id: '002')]
    matches = described_class.resolve(rows)
    expect(matches.map(&:team)).to eq([nil, nil])
    expect(matches.flat_map(&:suggestions).join).to include('Multiple source IDs')
  end
end
