# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/performance/fixture')

RSpec.describe OffseasonPerformance::ComparisonFixture do
  let(:season) { create(:season, year: 2026, start_date: '2025-11-01', end_date: '2026-04-10') }

  def replay
    fixture = JSON.parse(Rails.root.join('spec/fixtures/ingestion/cbbd/final.json').read)
    game = fixture.fetch('games').first
    %w[home away].each do |side|
      team = create(:team, school: game.fetch("#{side}Team"))
      create(:team_season, team:, season:)
      TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: game.fetch("#{side}TeamId").to_s)
    end
    entry = lambda do |raw|
      { 'raw' => raw, 'provenance' => { 'id' => 'synthetic', 'captured_at' => '2025-11-02T00:00:00Z' } }
    end
    row = Ingestion::Cbbd::Normalizer.new(entry.call(game), fixture.fetch('boxes').map(&entry)).call
    Ingestion::Cbbd::ImportObservation.new(row, season).call
    { 'bounds' => { 'season' => 2026, 'start_date' => '2025-11-01', 'end_date' => '2026-04-10' },
      'observations' => [row], 'complete' => true }
  end

  def create_run(value)
    run = CbbdReviewRun.create!(season:, start_date: '2025-11-01', end_date: '2026-04-10', status: 'completed',
                                maximum_requests: 20, retries: 0, normalized_replay: value,
                                manifest: { 'finalized' => true, 'acquisition' => { 'captures' => [] } })
    run.update!(evidence_digest: run.evidence_hash)
    run
  end

  it 'matches canonical bytes for reordered nested JSON and the JSONB round trip, using a fresh digest each call' do
    value = { 'z' => [nil, true, false, 12, -2, 1.25, "Unicode 🏀 é\n\"\\"], 'a' => { 'y' => 2, 'b' => [] } }
    connection = ActiveRecord::Base.connection
    stored = JSON.parse(connection.select_value("SELECT #{connection.quote(JSON.generate(value))}::jsonb::text"))
    expect(Departures::CanonicalDigest.new.call(value)).to eq(SeasonMembershipProposal.digest(value))
    expect(Departures::CanonicalDigest.new.call(stored)).to eq(SeasonMembershipProposal.digest(stored))
    expect(Departures::CanonicalDigest.new.call([value, stored])).to eq(SeasonMembershipProposal.digest([value, stored]))
    expect(Departures::CanonicalDigest.new.call({})).to eq(SeasonMembershipProposal.digest({}))
  end

  it 'matches real RunReview reports, fingerprints and shadows and passes the unchanged reloaded verifier' do
    value = replay
    ordinary = Ingestion::Reconciliation::RunReview.new(create_run(value)).compare
    run = create_run(value)
    builder = described_class.builder(run.id)
    allow(OffseasonPerformance::Fixture).to receive(:guard!)
    id = described_class.persist(builder, run.id)
    actual = CbbdReviewComparison.find(id)
    expect(actual.report).to eq(ordinary.report)
    expect(actual.artifact_digest).to eq(ordinary.artifact_digest)
    expect { actual.verify_artifact }.not_to raise_error
    expect(run.reload.active_comparison_id).to eq(id)
  end

  it 'rolls back the new artifact and active pointer when a staged write fails' do
    run = create_run(replay)
    builder = described_class.builder(run.id)
    allow(OffseasonPerformance::Fixture).to receive(:guard!)
    allow(described_class).to receive(:verify_column).and_raise('failed verification')
    expect { described_class.persist(builder, run.id) }.to raise_error('failed verification')
    expect(run.comparisons.count).to eq(0)
    expect(run.reload.active_comparison_id).to be_nil
  end

  it 'rejects replacing existing artifacts and preserves application immutability and tamper detection' do
    run = create_run(replay)
    ordinary = Ingestion::Reconciliation::RunReview.new(run).compare
    allow(OffseasonPerformance::Fixture).to receive(:guard!)
    expect { described_class.persist(described_class.builder(run.id), run.id) }.to raise_error(/existing comparison/)
    expect { ordinary.update!(report: {}) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    connection = CbbdReviewComparison.connection
    connection.execute("UPDATE cbbd_review_comparisons SET report = '{}'::jsonb WHERE id = #{ordinary.id}")
    expect { ordinary.reload.verify_artifact }.to raise_error(Ingestion::Cbbd::CaptureStore::IntegrityError)
  end

  it 'rejects a changed replay through the unchanged verifier' do
    run = create_run(replay)
    comparison = Ingestion::Reconciliation::RunReview.new(run).compare
    CbbdReviewComparison.connection.execute("UPDATE cbbd_review_comparisons SET replay = '{}'::jsonb WHERE id = #{comparison.id}")
    expect { comparison.reload.verify_artifact }.to raise_error(Ingestion::Cbbd::CaptureStore::IntegrityError)
  end

  it 'rejects unknown columns and noninteger identifiers before issuing SQL' do
    expect { described_class.write_column(0, 'draft', {}) }.to raise_error(KeyError)
    expect { described_class.verify_column(0, 'draft', 'unused') }.to raise_error(KeyError)
    expect { described_class.write_column('1 OR 1=1', 'report', {}) }.to raise_error(ArgumentError)
    expect { described_class.verify_column('1 OR 1=1', 'replay', 'unused') }.to raise_error(ArgumentError)
  end
end
