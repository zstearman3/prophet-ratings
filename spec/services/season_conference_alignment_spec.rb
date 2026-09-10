# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SeasonConferenceAlignment do
  subject(:alignment) { described_class.new(year: season.year).call }

  let!(:season) { create(:season, year: 2026) }
  let(:previous_season) { create(:season, year: 2025) }
  let(:team) { create(:team, school: 'First University', url: '/cbb/schools/first/men/') }
  let(:conference) { create(:conference, name: 'Alpha Conference', slug: 'alpha', abbreviation: 'ALP') }
  let(:old_conference) { create(:conference, name: 'Old Conference') }
  let(:row) do
    { team_slug: 'first', team_name: 'First University', conference_slug: 'alpha',
      conference_name: 'Alpha Conference', conference_abbreviation: 'ALP' }
  end
  let(:rows) { [row] }
  let(:scraper) { instance_double(Scraper::ConferenceStandingsScraper, call: rows, source_url: 'https://example.test/standings') }

  before do
    team
    conference
    allow(Scraper::ConferenceStandingsScraper).to receive(:new).with(year: 2026).and_return(scraper)
  end

  it 'creates a membership for a recognized team without one' do
    result = alignment
    expect(result.created.size).to eq(1)
    expect(result).to be_success
    expect(team.conference_for(season)).to eq(conference)
  end

  it 'does not write or change timestamps when the existing range already matches' do
    membership = create(:team_conference, team:, conference:, start_season: previous_season)
    attributes = membership.attributes
    result = alignment
    expect(result.unchanged.size).to eq(1)
    expect(result.created + result.changed).to be_empty
    expect(membership.reload.attributes).to eq(attributes)
  end

  it 'closes a prior range, creates the switched membership, and preserves timestamps on rerun' do
    previous = create(:team_conference, team:, conference: old_conference, start_season: previous_season)
    expect(alignment.changed.size).to eq(1)
    expect(previous.reload.end_season).to eq(previous_season)
    attributes = TeamConference.order(:id).map(&:attributes)
    result = described_class.new(year: 2026).call
    expect(result.unchanged.size).to eq(1)
    expect(TeamConference.order(:id).map(&:attributes)).to eq(attributes)
  end

  it 'closes an overlapping bounded range' do
    previous = create(:team_conference, team:, conference: old_conference, start_season: previous_season, end_season: season)
    expect(alignment.changed.size).to eq(1)
    expect(previous.reload.end_season).to eq(previous_season)
  end

  it 'uses the stored source identity despite a renamed school' do
    row[:team_name] = 'Renamed University'
    expect(alignment.created.size).to eq(1)
  end

  it 'matches legacy source URLs' do
    team.update!(url: 'https://www.sports-reference.com/cbb/schools/first/')
    expect(alignment.created.size).to eq(1)
  end

  it 'reports unmatched teams without creating teams or memberships' do
    row[:team_slug] = 'unknown'
    result = alignment
    expect(result.suggestions.join).to include('unmatched_team')
    expect(result).not_to be_success
    expect(Team.count).to eq(1)
    expect(TeamConference.count).to eq(0)
  end

  it 'uses exact aliases only when the stored source identity is unavailable' do
    team.update!(url: 'legacy')
    team.team_aliases.create!(value: 'Alternate University')
    row[:team_name] = 'Alternate University'
    expect(alignment.created.size).to eq(1)
  end

  it 'reports ambiguous stored source identities' do
    create(:team, url: team.url)
    expect(alignment.suggestions.join).to include('ambiguous_team', 'candidate ids=')
    expect(TeamConference.count).to eq(0)
  end

  it 'reports ambiguous fallback aliases' do
    team.update!(url: 'legacy')
    other = create(:team)
    other.team_aliases.create!(value: team.school)
    expect(alignment.suggestions.join).to include('ambiguous_team')
  end

  it 'reports unmatched conferences without creating them' do
    row.merge!(conference_slug: 'unknown', conference_name: 'Unknown', conference_abbreviation: 'UNK')
    expect(alignment.suggestions.join).to include('unmatched_conference')
    expect(Conference.count).to eq(1)
    expect(TeamConference.count).to eq(0)
  end

  it 'matches conferences by exact abbreviation when source slugs differ' do
    row[:conference_slug] = 'different'
    row[:conference_name] = 'Different'
    expect(alignment.created.size).to eq(1)
  end

  it 'reports conflicting conference identity matches as ambiguous' do
    create(:conference, abbreviation: 'ALP')
    expect(alignment.suggestions.join).to include('ambiguous_conference')
    expect(TeamConference.count).to eq(0)
  end

  it 'reports absent target-season teams and conferences while applying safe changes' do
    absent_team = create(:team)
    create(:team_conference, team: absent_team, conference: old_conference, start_season: previous_season)
    result = alignment
    expect(result.suggestions.join).to include('absent_team', 'absent_conference')
    expect(result.created.size).to eq(1)
    expect(absent_team.conference_for(season)).to eq(old_conference)
    expect(result).not_to be_success
  end

  it 'does not treat historical TeamSeasons or expired memberships as an expected current roster' do
    historical = create(:team)
    create(:team_season, team: historical, season:)
    create(:team_conference, team: historical, conference: old_conference, start_season: previous_season, end_season: previous_season)
    expect(alignment).to be_success
  end

  it 'reports a conflicting range starting in the target season for manual correction' do
    membership = create(:team_conference, team:, conference: old_conference, start_season: season)
    expect(alignment.suggestions.join).to include('membership_conflict')
    expect(membership.reload.conference).to eq(old_conference)
  end

  it 'rejects all duplicate source data before applying even a valid first row' do
    rows << row.dup
    expect { alignment }.to raise_error(Scraper::ConferenceStandingsScraper::Error, /Duplicate/)
    expect(TeamConference.count).to eq(0)
  end

  it 'rejects invalid source data before writes' do
    rows << row.merge(team_slug: nil)
    expect { alignment }.to raise_error(Scraper::ConferenceStandingsScraper::Error, /Invalid/)
    expect(TeamConference.count).to eq(0)
  end

  it 'rejects two source rows resolving to one fallback team before writes' do
    team.update!(url: 'legacy')
    rows << row.merge(team_slug: 'other')
    expect { alignment }.to raise_error(described_class::Error, /same stored team/)
    expect(TeamConference.count).to eq(0)
  end

  it 'rolls back all membership writes if a later assignment fails' do
    previous = create(:team_conference, team:, conference: old_conference, start_season: previous_season)
    other = create(:team, url: '/cbb/schools/other/men/')
    future = create(:season, year: 2027)
    create(:team_conference, team: other, conference:, start_season: future)
    rows << row.merge(team_slug: 'other', team_name: other.school)
    expect { alignment }.to raise_error(described_class::Error, /rolled back.*overlaps/)
    expect(TeamConference.count).to eq(2)
    expect(previous.reload.end_season).to be_nil
    expect(team.conference_for(season)).to eq(old_conference)
  end

  it 'does not retain stale ranges or suggestions when the same service is called twice' do
    service = described_class.new(year: 2026)
    first = service.call
    second = service.call
    expect(first.created.size).to eq(1)
    expect(second.created).to be_empty
    expect(second.unchanged.size).to eq(1)
  end

  it 'does not change stored memberships after a source request failure' do
    membership = create(:team_conference, team:, conference: old_conference, start_season: previous_season)
    allow(scraper).to receive(:call).and_raise(Scraper::ConferenceStandingsScraper::Error, 'HTTP 403')
    expect { alignment }.to raise_error(Scraper::ConferenceStandingsScraper::Error, /HTTP 403/)
    expect(membership.reload.end_season).to be_nil
    expect(TeamConference.count).to eq(1)
  end

  it 'fails without modifying a prior membership if the preceding season is missing' do
    earlier = create(:season, year: 2024)
    membership = create(:team_conference, team:, conference: old_conference, start_season: earlier)
    expect { alignment }.to raise_error(described_class::Error, /preceding season/)
    expect(membership.reload.end_season).to be_nil
  end

  it 'fails when the requested season does not exist' do
    expect { described_class.new(year: 2099) }.to raise_error(ArgumentError, /No season found/)
  end

  it 'fails clearly without any stored seasons' do
    season.destroy!
    expect { described_class.new }.to raise_error(ArgumentError, /No stored season/)
  end
end
