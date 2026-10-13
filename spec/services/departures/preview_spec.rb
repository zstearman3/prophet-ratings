# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe Departures::Preview do
  let(:directory) { Dir.mktmpdir('departures-preview') }
  let(:team) { create(:team, school: 'Sample School') }
  let(:other_team) { create(:team, school: 'Other School') }
  let(:identity) { Departures::TeamIdentity.new(teams: [team, other_team]) }
  let(:sources) do
    [snapshot('draft', 'nba_results', 'https://www.nba.com/news/2025-nba-draft-order', 'draft.html'),
     snapshot('school', 'sidearm_totals', 'https://school.example/sports/mens-basketball/stats/2024-25', 'school.html')
       .merge('team_name_source' => 'Sample School', 'scope' => Departures::Contract::SCOPE, 'scope_evidence' => 'Verified final scope')]
  end
  let(:manifest) do
    { 'draft_year' => 2025, 'prior_season_year' => 2025, 'target_year' => 2026, 'expected_picks' => (1..60).to_a, 'sources' => sources }
  end
  let(:dataset) { Departures::AnnualDataset.new(manifest:, directory:).call }
  let(:decisions) do
    [eligible('2025/1', 'alpha/101')] + (2..59).map do |pick|
      { 'selection_key' => "2025/#{pick}", 'status' => 'verified_no_college', 'reason' => 'Synthetic reviewed no-college evidence',
        'evidence_source_ids' => ['draft'] }
    end + [eligible('2025/60', 'beta/102')]
  end
  let(:review) do
    { 'dataset_revision' => dataset.fetch('dataset_revision'), 'revision_id' => 'review-1', 'reviewed_by' => 'Test reviewer',
      'reviewed_at' => '2026-10-13T12:00:00Z', 'decision' => 'approved', 'decisions' => decisions }
  end
  let(:report) { described_class.new(dataset:, review:, identity:).call }

  after { FileUtils.remove_entry(directory) }

  def snapshot(id, type, url, fixture)
    bytes = Rails.root.join('spec/fixtures/departures', fixture).binread
    sha = Digest::SHA256.hexdigest(bytes)
    File.binwrite(File.join(directory, "#{sha}.html"), bytes)
    { 'id' => id, 'type' => type, 'url' => url, 'snapshot_sha256' => sha, 'snapshot_location' => "#{sha}.html",
      'snapshot_kind' => 'raw_html', 'http_status' => 200, 'captured_at' => '2026-10-13T11:00:00Z',
      'observed_at' => '2026-10-13T11:00:00Z', 'source_as_of' => nil, 'source_as_of_reason' => 'Unavailable' }
  end

  def eligible(key, player)
    { 'selection_key' => key, 'status' => 'eligible_prior_season', 'reason' => 'Reviewed draft profile and prior-season roster identity',
      'evidence_source_ids' => %w[draft school],
      'stints' => [{ 'source_id' => 'school', 'player_source_url' => "https://school.example/sports/mens-basketball/roster/#{player}",
                     'team_id' => team.id, 'identity_evidence_source_ids' => %w[draft school] }] }
  end

  it 'preserves multiple departures, zero production and verified zero for other teams' do
    expect(report.fetch('teams').first).to include('known_points_subtotal' => 500, 'team_points' => 2000, 'loss_share' => 0.25)
    expect(report.fetch('teams').last).to include('loss_share' => 0.0, 'reason' => 'verified_zero')
    expect(report.fetch('selections').last.fetch('stints').first).to include('games' => 2, 'player_points' => 0)
    expect(report.fetch('reviewed_revision')).to eq(Departures::Contract.digest(review))
  end

  it 'leaves unreviewed professional affiliations unknown rather than no-college' do
    dataset.fetch('selections').last['affiliation_source'] = 'International Club'
    dataset['dataset_revision'] = Departures::Contract.digest(dataset.except('dataset_revision'))
    result = described_class.new(dataset:, identity:).call
    expect(result.fetch('status_counts')).to eq('unknown_participation' => 60)
    expect(result.fetch('teams').pluck('loss_share')).to eq([nil, nil])
  end

  it 'keeps known subtotals but all team losses null when a selection is globally unresolved' do
    decisions.pop
    expect(report.fetch('teams').first).to include('known_points_subtotal' => 500, 'loss_share' => nil)
    expect(report.fetch('teams').last.fetch('loss_share')).to be_nil
  end

  it 'limits unknown production to the uniquely identified affected team' do
    decisions.last.replace('selection_key' => '2025/60', 'status' => 'unknown_production', 'reason' => 'Final totals unavailable',
                           'team_name_source' => team.school, 'team_source' => 'school.example', 'evidence_source_ids' => ['draft'])
    expect(report.fetch('teams').first.fetch('loss_share')).to be_nil
    expect(report.fetch('teams').last.fetch('loss_share')).to eq(0.0)
  end

  %w[verified_no_college verified_nonparticipant outside_prior_season].each do |status|
    it "counts reviewed #{status} evidence without adding production" do
      decisions.last.replace('selection_key' => '2025/60', 'status' => status,
                             'reason' => 'Reviewed full prior-season participation evidence', 'evidence_source_ids' => ['draft'])
      expect(report.fetch('teams').first.fetch('loss_share')).to eq(0.25)
      expect(report.fetch('selections').last.fetch('stints')).to be_empty
    end
  end

  it 'does not claim completeness when an expected selection is missing' do
    dataset.fetch('selections').delete_at(58)
    decisions.delete_at(58)
    dataset['dataset_revision'] = Departures::Contract.digest(dataset.except('dataset_revision'))
    expect(report.fetch('draft_complete')).to be false
    expect(report.fetch('teams').pluck('loss_share')).to eq([nil, nil])
  end

  it 'rejects undrafted reviewed candidates and duplicate decisions' do
    decisions << eligible('2025/61', 'other/103')
    expect { report }.to raise_error(ArgumentError, /undrafted/)
    decisions.last['selection_key'] = '2025/60'
    expect { report }.to raise_error(ArgumentError, /Duplicate review/)
  end

  it 'requires reviewed roster IDs instead of guessing from names' do
    decisions.last.fetch('stints').first['player_source_url'] = 'https://school.example/not-a-player'
    expect { report }.to raise_error(ArgumentError, /school player identity/)
  end

  it 'rejects duplicate school player identities across distinct selections' do
    decisions.last.fetch('stints').first['player_source_url'] = decisions.first.fetch('stints').first.fetch('player_source_url')
    expect { report }.to raise_error(ArgumentError, /Duplicate school player/)
  end

  it 'requires approved dataset and reviewer identity' do
    review['dataset_revision'] = 'wrong'
    expect { report }.to raise_error(ArgumentError, /another dataset/)
    review['dataset_revision'] = dataset.fetch('dataset_revision')
    review['reviewed_by'] = ''
    expect { report }.to raise_error(ArgumentError, /reviewed_by/)
  end

  it 'rejects unsupported production, nonparticipation stints and failed participation evidence' do
    decisions.last.fetch('stints').first['source_id'] = 'unknown'
    expect { report }.to raise_error(ArgumentError, /production source/)
    decisions.last.delete('stints')
    expect { report }.to raise_error(ArgumentError, /requires production/)
    decisions.last['evidence_source_ids'] = ['unknown']
    expect { report }.to raise_error(ArgumentError, /Evidence source/)
  end

  it 'collects conflicting canonical and source alias owners without selecting one' do
    create(:team_alias, team: other_team, source: 'school.example', value: team.school)
    resolver = Departures::TeamIdentity.new(teams: Team.includes(:team_aliases).order(:id).to_a)
    expect(resolver.candidates(team.school, source: 'school.example')).to eq([team.id, other_team.id].sort)
    expect { described_class.new(dataset:, review:, identity: resolver).call }.to raise_error(ArgumentError, /candidates/)
  end

  it 'excludes aliases from other sources and preserves punctuation/internal spacing' do
    create(:team_alias, team: other_team, source: 'another.example', value: 'Sample School')
    team
    resolver = Departures::TeamIdentity.new(teams: Team.includes(:team_aliases).order(:id).to_a)
    expect(resolver.candidates(' Sample School ', source: 'school.example')).to eq([team.id])
    expect(resolver.candidates('Sample  School', source: 'school.example')).to be_empty
    expect(resolver.candidates('sample school', source: 'school.example')).to be_empty
  end

  it 'uses each evidenced team stint with its own team denominator' do
    sources << sources.last.merge('id' => 'other-school', 'url' => 'https://other.example/sports/mens-basketball/stats/2024-25',
                                  'team_name_source' => other_team.school)
    decisions.first.fetch('stints') << { 'source_id' => 'other-school', 'team_id' => other_team.id,
                                         'player_source_url' => 'https://other.example/sports/mens-basketball/roster/alpha/101',
                                         'identity_evidence_source_ids' => %w[other-school draft] }
    expect(report.fetch('teams').pluck('loss_share')).to eq([0.25, 0.25])
    expect(report.fetch('selections').first.fetch('stints').size).to eq(2)
  end

  it 'keeps unknown participation global even when an affiliation matches one team' do
    decisions.last.replace('selection_key' => '2025/60', 'status' => 'unknown_participation',
                           'team_name_source' => team.school, 'team_source' => 'school.example',
                           'reason' => 'Affiliation is not complete participation evidence', 'evidence_source_ids' => ['draft'])
    expect(report.fetch('teams').pluck('loss_share')).to eq([nil, nil])
  end

  it 'rejects conflicting production denominators from multiple source revisions' do
    sources << sources.last.merge('id' => 'school-revision')
    decisions.last.fetch('stints').first['source_id'] = 'school-revision'
    expect { report }.to raise_error(ArgumentError, /Conflicting team denominators/)
  end

  it 'performs no application writes while acquiring coverage' do
    team
    other_team
    expect { report }.not_to(change { [Team.count, TeamSeason.count, TeamOffseasonProfile.count, TeamRatingSnapshot.count] })
  end
end
