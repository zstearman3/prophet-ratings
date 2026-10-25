# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SeasonMembershipReview, :cbbd do
  let!(:previous) { create(:season, year: 2026) }
  let!(:season) { create(:season, year: 2027) }
  let!(:following) { create(:season, year: 2028) }
  let!(:team) { create(:team) }
  let!(:old) { create(:conference) }
  let!(:conference) { create(:conference) }
  let(:review) { described_class.new(season) }
  let(:source) do
    { 'provider' => 'cbbd', 'source_url' => 'https://api.collegebasketballdata.com/teams/directory?season=2027',
      'captured_at' => '2026-10-21T12:00:00Z', 'acquisition' => { 'version' => 1, 'captures' => [] },
      'source_rows' => [{ team_external_id: '001', team_name: 'Renamed school', conference_external_id: '10',
                          conference_name: 'Renamed conference', conference_abbreviation: 'RC' }] }
  end

  before do
    create(:team_alias, team:, value: team.school)
    create(:team_season, team:, season:)
    TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: '001')
    ConferenceExternalIdentity.associate!(conference:, provider: 'cbbd', external_id: '10')
    create(:team_conference, team:, conference: old, start_season: previous)
    allow(Ingestion::Cbbd::MembershipDirectory).to receive(:new).and_return(double(call: source))
    allow(Scraper::ConferenceStandingsScraper).to receive(:new).and_raise('Unexpected Sports Reference request')
  end

  def refresh
    review.refresh(provider: 'cbbd')
  end

  def submission
    { 'proposal_key' => review.proposal_key, 'start_date' => season.start_date.iso8601,
      'end_date' => season.end_date.iso8601, 'evidence' => 'Checked official roster',
      'confirm_source_coverage' => '1', 'teams' => { team.id.to_s => { 'choice' => conference.id.to_s, 'reason' => '' } } }
  end

  it 'fetches only a retained proposal and resolves renamed labels by exact IDs' do
    before = [team.attributes, old.attributes, conference.attributes, TeamConference.all.map(&:attributes)]
    refresh
    expect(season.reload.membership_proposal).to include('provider' => 'cbbd', 'acquisition' => source['acquisition'])
    expect(season.membership_proposal['rows'].sole['choice']).to eq(conference.id.to_s)
    expect([team.reload.attributes, old.reload.attributes, conference.reload.attributes,
            TeamConference.all.map(&:attributes)]).to eq(before)
  end

  it 'requires explicit coverage confirmation and preserves surrounding membership years' do
    refresh
    expect { review.apply(submission.except('confirm_source_coverage'), reviewer: 'admin') }.to raise_error(ArgumentError, /coverage/)
    review.apply(submission, reviewer: 'admin')
    expect(team.conference_for(previous)).to eq(old)
    expect(team.conference_for(season)).to eq(conference)
    expect(team.conference_for(following)).to eq(old)
    expect(season.reload.participation_review['source_coverage_confirmed']).to be(true)
  end

  it 'rejects stale identity changes before mapping or approval' do
    refresh
    attributes = submission
    TeamExternalIdentity.create!(team:, provider: 'cbbd', external_id: '002')
    expect { review.apply(attributes, reviewer: 'admin') }.to raise_error(ArgumentError, /Local roster/)
    expect { SeasonConferenceMapping.new(season).call('proposal_key' => review.proposal_key, 'conferences' => {}) }
      .to raise_error(ArgumentError, /Local roster/)
  end

  it 'proposes unique label matches for unknown IDs but requires saving them before roster approval' do
    source['source_rows'].first[:team_external_id] = '999'
    source['source_rows'].first[:team_name] = team.school
    refresh
    expect(season.membership_proposal['issues']).to be_empty
    expect(season.membership_proposal['rows'].sole['choice']).to eq(conference.id.to_s)
    expect { SeasonSchoolImport.new(season).preview('proposal_key' => review.proposal_key) }.to raise_error(ArgumentError, /manual/i)
    expect { review.apply(submission, reviewer: 'admin') }.to raise_error(ArgumentError, /Save CBBD identity matches/)
  end

  it 'retains unknown source schools until explicit manual setup and a fresh fetch' do
    source['source_rows'] << source['source_rows'].first.merge(team_external_id: '002', team_name: 'New U')
    refresh
    expect(season.membership_proposal['issues'].join).to include('New U')
    newcomer = create(:team, school: 'New U', url: '/cbb/schools/verified-new/men/')
    create(:team_alias, team: newcomer, value: 'New U')
    create(:team_season, team: newcomer, season:)
    TeamExternalIdentity.associate!(team: newcomer, provider: 'cbbd', external_id: '002')
    refresh
    expect(season.membership_proposal['issues']).to be_empty
    expect(season.membership_proposal['rows'].size).to eq(2)
  end

  it 'rolls back all decisions when a required adjacent boundary season is missing' do
    following.destroy!
    refresh
    before = TeamConference.order(:id).map(&:attributes)
    expect { review.apply(submission, reviewer: 'admin') }.to raise_error(ArgumentError, /boundary season YEAR=2028/)
    expect(TeamConference.order(:id).map(&:attributes)).to eq(before)
    expect(season.reload.participation_review).to eq({})
  end

  it 'keeps absent local schools unresolved and requires reasons for explicit exclusions' do
    absent = create(:team)
    refresh
    row = season.membership_proposal['rows'].find { |item| item['team_id'] == absent.id }
    expect(row).to include('choice' => 'unresolved')
    attributes = submission
    attributes['teams'][absent.id.to_s] = { 'choice' => 'unresolved' }
    expect { review.apply(attributes, reviewer: 'admin') }.to raise_error(ArgumentError, /choose a membership/)
    attributes['teams'][absent.id.to_s] = { 'choice' => 'excluded', 'reason' => 'Verified D1 departure' }
    review.apply(attributes, reviewer: 'admin')
    expect(season.reload.participation_review['teams']).to include(hash_including('team_id' => absent.id, 'status' => 'excluded'))
  end

  it 'rejects duplicate source identities that map to the same local team' do
    TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: '002')
    source['source_rows'] << source['source_rows'].first.merge(team_external_id: '002')
    refresh
    expect(season.membership_proposal['issues'].join).to include('Multiple source IDs')
    expect { review.apply(submission, reviewer: 'admin') }.to raise_error(ArgumentError, /Resolve source identities/)
  end

  it 'rejects identity changes during acquisition without replacing the draft' do
    refresh
    original = season.membership_proposal
    directory = double
    allow(directory).to receive(:call) do
      TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: '002')
      source
    end
    allow(Ingestion::Cbbd::MembershipDirectory).to receive(:new).and_return(directory)
    expect { refresh }.to raise_error(ArgumentError, /changed during discovery/)
    expect(season.reload.membership_proposal).to eq(original)
  end

  it 'requires previous-year confirmation in addition to source coverage' do
    review.refresh(provider: 'cbbd', source_year: 2026)
    expect { review.apply(submission, reviewer: 'admin') }.to raise_error(ArgumentError, /target-year verification/)
    review.apply(submission.merge('confirm_target_year' => '1'), reviewer: 'admin')
    expect(season.reload.participation_review['membership_source']).to include('provider' => 'cbbd', 'source_year' => 2026)
  end

  %w[independent excluded].each do |choice|
    it "preserves finite future history for a full #{choice} decision" do
      membership = team.team_conferences.sole
      membership.update!(end_season: following)
      other = create(:team)
      create(:team_alias, team: other, value: other.school)
      create(:team_season, team: other, season:)
      TeamExternalIdentity.associate!(team: other, provider: 'cbbd', external_id: '002')
      source['source_rows'] << source['source_rows'].first.merge(team_external_id: '002')
      refresh
      attributes = submission
      attributes['teams'][other.id.to_s] = { 'choice' => conference.id.to_s }
      attributes['teams'][team.id.to_s] = { 'choice' => choice, 'reason' => 'Verified target-year evidence' }
      review.apply(attributes, reviewer: 'admin')
      expect([previous, season, following].map { |year| team.conference_for(year) }).to eq([old, nil, old])
      expect(TeamConference.find_by!(team:, start_season: following).end_season).to eq(following)
    end
  end

  it 'preserves future history when the original membership starts at the target' do
    team.team_conferences.sole.update!(start_season: season)
    refresh
    review.apply(submission, reviewer: 'admin')
    expect([previous, season, following].map { |year| team.conference_for(year) }).to eq([nil, conference, old])
  end

  it 'does not rewrite an unchanged membership or its timestamp' do
    membership = team.team_conferences.sole
    membership.update!(conference:)
    original = membership.attributes
    refresh
    review.apply(submission, reviewer: 'admin')
    expect(membership.reload.attributes).to eq(original)
  end

  it 'atomically rolls back multiple conference mappings when a later selected ID is invalid' do
    ConferenceExternalIdentity.destroy_all
    source['source_rows'] << source['source_rows'].first.merge(team_external_id: '002', conference_external_id: '20')
    refresh
    original = season.membership_proposal
    expect do
      SeasonConferenceMapping.new(season).call('proposal_key' => review.proposal_key,
                                               'conferences' => { '10' => conference.id.to_s,
                                                                  '20' => '999999999' })
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(ConferenceExternalIdentity.count).to eq(0)
    expect(season.reload.membership_proposal).to eq(original)
  end
end
