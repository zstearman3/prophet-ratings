# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Departures::CbbdDataset do
  let(:directory) { Dir.mktmpdir('cbbd-departures') }
  let(:plan) do
    { 'provider' => 'cbbd', 'schema' => 'draft-departures-v2', 'extraction_version' => 'cbbd-draft-season-totals-v1',
      'draft_year' => 2025, 'prior_season_year' => 2025, 'target_year' => 2026, 'expected_picks' => [1, 59],
      'scope_evidence' => 'Reviewed completed final regular and postseason scope', 'max_requests' => 10, 'retries' => 1 }
  end
  let(:picks) do
    [{ 'year' => 2025, 'overall' => 1, 'round' => 1, 'pick' => 1, 'name' => 'Alpha', 'athleteId' => 10,
       'sourceTeamCollegeId' => 20, 'sourceTeamLocation' => 'Sample', 'sourceTeamName' => 'School' },
     { 'year' => 2025, 'overall' => 59, 'round' => 2, 'pick' => 29, 'name' => 'International', 'athleteId' => nil,
       'sourceTeamCollegeId' => nil, 'sourceTeamLocation' => 'Club' }]
  end
  let(:regular_players) { [player(10, 400, 8), player(11, 1200, 8), player(12, 0, 1)] }
  let(:post_players) { [player(10, 100, 2), player(11, 300, 2), player(12, 0, 1)] }
  let(:rows) { [picks, regular_players, post_players, [team(1600, 8)], [team(400, 2)]] }

  after { FileUtils.remove_entry(directory) }

  def player(id, points, games)
    { 'season' => 2025, 'athleteId' => id, 'athleteSourceId' => "upstream-#{id}", 'name' => "Player #{id}",
      'teamId' => 20, 'team' => 'Sample School', 'conference' => 'Sample', 'points' => points, 'games' => games, 'minutes' => 20.5 }
  end

  def team(points, games)
    { 'season' => 2025, 'teamId' => 20, 'team' => 'Sample School', 'games' => games,
      'totalMinutes' => 40 * games, 'teamStats' => { 'points' => { 'total' => points } } }
  end

  def saved_manifest
    sources = Departures::CbbdDataset.sources(plan).zip(rows).map do |source, payload|
      bytes = JSON.generate(payload)
      sha = Digest::SHA256.hexdigest(bytes)
      File.binwrite(File.join(directory, "#{sha}.json"), bytes)
      source.merge('snapshot_sha256' => sha, 'snapshot_location' => "#{sha}.json", 'snapshot_kind' => 'raw_json',
                   'http_status' => 200, 'captured_at' => '2026-01-01T00:00:00Z', 'observed_at' => '2026-01-01T00:00:00Z',
                   'source_as_of_reason' => 'Provider has no publication timestamp', 'sanitized' => false)
    end
    sources.each_with_index { |source, index| source['selected_capture_id'] = "capture-#{index + 1}" }
    captures = sources.map { |source| source.except('selected_capture_id').merge('id' => source.fetch('selected_capture_id')) }
    plan.merge('sources' => sources, 'captures' => captures)
  end

  def dataset
    Departures::AnnualDataset.new(manifest: saved_manifest, directory:).call
  end

  it 'retains both rounds and nullable identities and sums disjoint scopes with independent denominators' do
    facts = dataset
    expect(facts.fetch('failures')).to be_empty
    expect(facts.fetch('selections').last['provider_athlete_id']).to be_nil
    table = facts.fetch('production').first
    expect(table.slice('team_points', 'team_minutes')).to eq('team_points' => 2000, 'team_minutes' => 123.0)
    expect(table.fetch('players').pluck('player_points')).to eq([500, 1500, 0])
    expect(table.fetch('players').first['scope_rows'].size).to eq(2)
  end

  it 'rejects offsetting per-scope discrepancies before combining the season' do
    regular_players.first['points'] = 500
    post_players.first['points'] = 0
    expect(dataset.fetch('failures').pluck('failure').join).to include('regular')
  end

  it 'preserves a missing postseason player as unknown even when zero scoring could reconcile' do
    post_players.pop
    facts = dataset
    expect(facts.fetch('production').first.fetch('players').last['coverage_complete']).to be(false)
  end

  it 'does not certify empty successful responses or missing team scopes as observed zero' do
    rows[4] = []
    expect(dataset.fetch('production').first['coverage_complete']).to be(false)
  end

  it 'rejects fractional points and duplicate scope identities' do
    regular_players.first['points'] = 400.5
    expect(dataset.fetch('failures').pluck('failure').join).to include('points')
    regular_players.first['points'] = 400
    regular_players << regular_players.first.dup
    expect(dataset.fetch('failures').pluck('failure').join).to include('Duplicate')
  end

  it 'replays offline and rejects altered bytes' do
    original = dataset
    expect(Departures::AnnualDataset.new(manifest: original.except('dataset_revision', 'selections', 'production', 'failures'),
                                         directory:).call)
      .to eq(original)
    File.binwrite(File.join(directory, original.fetch('sources').first.fetch('snapshot_location')), '[]')
    expect { described_class.new(manifest: original, directory:).call }.to raise_error(ArgumentError, /hash/)
  end

  it 'does not let a reviewed whole-team absence excuse a missing player when postseason production exists' do
    plan['absent_postseason_team_ids'] = [20]
    post_players.pop
    expect(dataset.fetch('production').first.fetch('players').last['coverage_complete']).to be(false)
  end

  it 'retains legitimate reviewed whole-team postseason absence without inventing zero rows' do
    plan['absent_postseason_team_ids'] = [20]
    rows[2] = []
    rows[4] = []
    table = dataset.fetch('production').first
    expect(table.fetch('coverage_complete')).to be(true)
    expect(table.fetch('scope_rows')['postseason']).to be_nil
    expect(table.fetch('players').first['player_points']).to eq(400)
  end

  it 'rejects missing or duplicated logical sources rather than certifying partial requests' do
    incomplete = saved_manifest
    incomplete.fetch('sources').pop
    expect { described_class.new(manifest: incomplete, directory:).call }.to raise_error(ArgumentError, /five|sources/)
    duplicate = saved_manifest
    duplicate.fetch('sources') << duplicate.fetch('sources').first
    expect { described_class.new(manifest: duplicate, directory:).call }.to raise_error(ArgumentError, /five|sources/)
  end

  it 'rejects an endpoint filter that omits other prior-season stints' do
    manifest = saved_manifest
    manifest['sources'][1]['request']['team'] = 'Sample School'
    expect { described_class.new(manifest:, directory:).call }.to raise_error(ArgumentError, /request/)
  end

  it 'preserves nullable team game-clock minutes as unknown audit data without changing the points denominator' do
    rows[3].first['totalMinutes'] = nil
    table = dataset.fetch('production').first
    expect(table['team_points']).to eq(2000)
    expect(table.dig('scope_rows', 'regular', 'team_game_clock_minutes')).to be_nil
  end

  it 'rejects a selected response whose retry ledger has been removed' do
    manifest = saved_manifest
    manifest['captures'] = []
    expect { described_class.new(manifest:, directory:).call }.to raise_error(ArgumentError, /capture|ledger/)
  end

  it 'retains null player points as unknown production without discarding the independent team denominator' do
    regular_players.first['points'] = nil
    facts = dataset
    expect(facts.fetch('failures')).to be_empty
    table = facts.fetch('production').first
    expect(table['team_points']).to eq(2000)
    expect(table.fetch('players').first).to include('player_points' => nil, 'coverage_complete' => false)
  end

  [['regular', 1, 1700], ['postseason', 2, 500]].each do |scope, index, subtotal|
    it "rejects a definite #{scope} points excess even when another player has unknown points" do
      rows[index][0]['points'] = subtotal
      rows[index][1]['points'] = nil
      expect(dataset.fetch('failures').pluck('failure').join).to include("#{scope} player/team points mismatch")
    end
  end

  [['regular', 1, 1600], ['postseason', 2, 400]].each do |scope, index, subtotal|
    it "keeps null #{scope} points unknown when the known subtotal exactly matches the denominator" do
      rows[index][0]['points'] = subtotal
      rows[index][1]['points'] = nil
      facts = dataset
      expect(facts.fetch('failures')).to be_empty
      expect(facts.fetch('production').first['coverage_complete']).to be(false)
      expect(facts.fetch('production').first['team_points']).to eq(2000)
    end
  end
end
