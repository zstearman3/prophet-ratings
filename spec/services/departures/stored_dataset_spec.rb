# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Departures::StoredDataset do
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

  def stored_attempt
    manifest = saved_manifest
    batch = DepartureBatch.create!(season: Season.create!(year: 2026, start_date: '2025-11-01', end_date: '2026-04-10'), plan:)
    attempt = batch.acquisitions.create!(plan:, manifest:, status: 'running')
    attempt.update!(evidence: Departures::CaptureStore.new(attempt).retain(manifest, directory))
    attempt
  end

  def expanded(attempt)
    record = described_class.new(attempt).call
    Departures::DatasetStream.new(record).expand
  end

  it 'preserves the full logical dataset and digest while storing shared bytes once' do
    attempt = stored_attempt
    legacy = Departures::AnnualDataset.new(manifest: attempt.manifest, directory:).call
    expect(expanded(attempt)).to eq(legacy)
    expect(DepartureCaptureObservation.count).to eq(5)
    expect(DepartureSourceCapture.count).to eq(5)
    refs = attempt.evidence.fetch('observations')
    expect(refs.fetch('draft')).to eq(refs.fetch('capture-1'))
    expect(attempt.evidence.to_json).not_to include('snapshot_base64')
  end

  it 'preserves independent request provenance and scope when bodies are identical' do
    rows[2] = rows[1]
    rows[4] = rows[3]
    first = stored_attempt
    record = described_class.new(first).call
    expect([DepartureSourceCapture.count, DepartureCaptureObservation.count]).to eq([3, 5])
    expect(record.source_normalization_ids.fetch('player-regular')).not_to eq(record.source_normalization_ids.fetch('player-postseason'))
    later = first.manifest.deep_dup
    Departures::RetainedEvidence.sources(later).each do |source|
      source.merge!('captured_at' => '2026-02-01T00:00:00Z', 'observed_at' => '2026-02-01T00:00:00Z')
    end
    second = first.departure_batch.acquisitions.create!(plan:, manifest: later, status: 'running')
    second.update!(evidence: Departures::CaptureStore.new(second).retain(second.manifest, directory))
    expect([DepartureSourceCapture.count, DepartureCaptureObservation.count]).to eq([3, 10])
    expect(second.evidence).not_to eq(first.evidence)
    original = DepartureCaptureObservation.find(first.evidence.fetch('observations').fetch('capture-1'))
    retained = DepartureCaptureObservation.find(second.evidence.fetch('observations').fetch('capture-1'))
    expect(retained).to have_attributes(departure_source_capture_id: original.departure_source_capture_id,
                                        departure_acquisition_id: second.id, metadata: later.fetch('captures').first,
                                        extraction_version: plan.fetch('extraction_version'))
  end

  it 'verifies persisted rows and rejects tampering before publication' do
    attempt = stored_attempt
    result = Departures::RetainedEvidence.new(attempt).acquisition_result
    attempt.update!(**result, finished_at: Time.current)
    expect(Departures::RetainedEvidence.new(attempt).verified_dataset(plan)).to eq(expanded(attempt))
    row = DepartureNormalizedRow.first
    corrupt_departure_fact(row, {})
    expect { Departures::RetainedEvidence.new(attempt).verified_dataset(plan) }.to raise_error(ArgumentError, /rows differ/)
  end

  it 'rejects mismatched selected provenance and unknown reference versions' do
    attempt = stored_attempt
    attempt.manifest['sources'][0]['observed_at'] = '2026-01-02T00:00:00Z'
    expect { described_class.new(attempt).call }.to raise_error(ArgumentError, /ledger mismatch/)
    attempt.evidence['storage_version'] = 'unknown'
    expect { Departures::RetainedEvidence.new(attempt).bytes('draft') }.to raise_error(ArgumentError, /storage version/)
  end

  %w[cbbd-draft-season-totals-v1 cbbd-draft-season-totals-v2].each do |extraction|
    it "keeps #{extraction} normalization results equivalent with missing points and zero participants" do
      plan['extraction_version'] = extraction
      regular_players.first['points'] = nil
      rows[3].first['totalMinutes'] = nil
      attempt = stored_attempt
      expect(expanded(attempt)).to eq(Departures::AnnualDataset.new(manifest: attempt.manifest, directory:).call)
    end
  end
  it 'preserves negative zero and exponent-valued raw JSON facts through PostgreSQL storage' do
    regular_players.first['minutes'] = -0.0
    regular_players.first['annotation'] = { 'tiny' => 1.25e-30, 'large' => 1e30 }
    attempt = stored_attempt
    original = Departures::AnnualDataset.new(manifest: attempt.manifest, directory:).call
    expect(expanded(attempt)).to eq(original)
    expect(expanded(attempt).fetch('dataset_revision')).to eq(original.fetch('dataset_revision'))
  end

  %w[cbbd-draft-season-totals-v3 cbbd-draft-season-totals-v4].each do |version|
    it "reuses source normalization without freezing a different #{version} annual policy" do
      first = stored_attempt
      strict = described_class.new(first).call
      plan.merge!('extraction_version' => version, 'scope_evidence' => { 'policy' => Departures::DraftTeamSnapshot::POLICY },
                  'draft_policy' => 'confirmed_retained_results', 'team_matches' => [{ 'provider_team_id' => 20, 'team_id' => 1 }])
      manifest = plan.merge(first.manifest.slice('sources', 'captures'))
      successor = first.departure_batch.acquisitions.create!(plan:, manifest:, evidence: first.evidence, status: 'running')
      automatic = described_class.new(successor).call
      expect(automatic.source_normalization_ids).to eq(strict.source_normalization_ids)
      expect(automatic.id).not_to eq(strict.id)
      expect(Departures::DatasetStream.new(automatic).expand)
        .to eq(Departures::AnnualDataset.new(manifest:, directory:).call)
    end
  end

  it 'makes cross-batch duplicate identities an explicit global failure without partial production' do
    rows[1] = Array.new(501) { |index| player(index + 1, 1, 1) }
    rows[1] << rows[1].first.deep_dup
    attempt = stored_attempt
    facts = expanded(attempt)
    expect(facts.fetch('production')).to eq([])
    expect(facts.fetch('failures').pluck('failure').join).to include('Duplicate regular athlete/team rows')
    expect(DepartureSourceNormalization.where(status: 'failed').count).to eq(1)
  end

  it 'keeps a wrong production year explicit with no partial production' do
    regular_players.first['season'] = 2024
    attempt = stored_attempt
    facts = expanded(attempt)
    expect(facts).to eq(Departures::AnnualDataset.new(manifest: attempt.manifest, directory:).call)
    expect(facts.fetch('production')).to eq([])
  end

  it 'never exposes an interrupted batch as complete and safely replaces incomplete rows on retry' do
    rows[1] = Array.new(501) { |index| player(index + 1, 1, 1) }
    attempt = stored_attempt
    source = attempt.manifest.fetch('sources').find { |entry| entry['id'] == 'player-regular' }
    bytes = Departures::RetainedEvidence.new(attempt).bytes('player-regular')
    calls = 0
    allow(Departures::SourceRowWriter).to receive(:new).and_wrap_original do |constructor, *arguments|
      writer = constructor.call(*arguments)
      allow(writer).to receive(:append).and_wrap_original do |method, batch|
        calls += 1
        raise IOError, 'Synthetic interrupted normalization' if calls == 2

        method.call(batch)
      end
      writer
    end
    expect { Departures::SourceNormalizer.new(source, bytes, plan).call }.to raise_error(IOError, /interrupted/)
    record = DepartureSourceNormalization.find_by!(status: 'running')
    expect(record.rows.count).to eq(0)
    allow(Departures::SourceRowWriter).to receive(:new).and_call_original
    complete = Departures::SourceNormalizer.new(source, bytes, plan).call
    expect(complete.status).to eq('completed')
    expect(complete.row_count).to eq(501)
    expect(complete.rows.count).to eq(501)
  end

  it 'retains immutable acquisition provenance and reuses references in correction successors' do
    attempt = stored_attempt
    result = Departures::RetainedEvidence.new(attempt).acquisition_result
    attempt.update!(**result, finished_at: Time.current)
    observation = DepartureCaptureObservation.first
    capture = observation.departure_source_capture
    expect { observation.update!(metadata: {}) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { capture.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    successor = attempt.departure_batch.acquisitions.create!(attempt.correction_attributes)
    expect(successor.evidence).to eq(attempt.evidence)
    expect(DepartureSourceCapture.count).to eq(5)
    expect(DepartureCaptureObservation.count).to eq(5)
  end

  it 'does not write domain identities, profiles, ratings or approval rows during normalization' do
    models = [Team, TeamSeason, TeamExternalIdentity, TeamOffseasonProfile, TeamRatingSnapshot, OffseasonInputRevision]
    before_counts = models.map(&:count)
    attempt = stored_attempt
    expanded(attempt)
    expect(models.map(&:count)).to eq(before_counts)
    expect(attempt.departure_batch.decisions).to eq([])
    expect(attempt.departure_batch.reviewed_at).to be_nil
  end

  it 'validates annual normalized records as well as raw captures before publication' do
    attempt = stored_attempt
    attempt.update!(**Departures::RetainedEvidence.new(attempt).acquisition_result, finished_at: Time.current)
    row = DepartureDatasetRow.where(kind: 'production').first
    corrupt_departure_fact(row, {})
    expect { Departures::RetainedEvidence.new(attempt).verified_dataset(plan) }.to raise_error(ArgumentError, /differs from replay/)
  end

  it 'fails closed when an observation or its body is missing or corrupt' do
    attempt = stored_attempt
    reference = attempt.evidence.fetch('observations').fetch('draft')
    observation = DepartureCaptureObservation.find(reference)
    corrupt_departure_capture(observation.departure_source_capture_id, 'corrupted')
    expect { Departures::RetainedEvidence.new(attempt).bytes('draft') }.to raise_error(ArgumentError, /hash|identity mismatch/)
    DepartureCaptureObservation.where(id: reference).delete_all
    expect { Departures::RetainedEvidence.new(attempt).bytes('draft') }.to raise_error(ArgumentError, /Missing retained/)
  end

  it 'writes annual output without instantiating or retaining an AR object per inserted row' do
    attempt = stored_attempt
    allow(DepartureDatasetRow).to receive(:new).and_call_original
    allow(DepartureNormalizedRow).to receive(:new).and_call_original
    largest_batch = 0
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      next unless payload.fetch(:class_name).in?(%w[DepartureDatasetRow DepartureNormalizedRow])

      largest_batch = [largest_batch, payload.fetch(:record_count)].max
    end
    ActiveSupport::Notifications.subscribed(subscriber, 'instantiation.active_record') { expanded(attempt) }
    expect(DepartureDatasetRow).not_to have_received(:new)
    expect(DepartureNormalizedRow).not_to have_received(:new)
    expect(largest_batch).to be <= Departures::JsonRows::BATCH_SIZE
    expect(DepartureDatasetRow.count).to be_positive
  end

  it 'rolls back interrupted annual output and retries without double-counting or certifying partial data' do
    attempt = stored_attempt
    writes = 0
    allow(Departures::EvidenceRows).to receive(:annual).and_wrap_original do |method, attributes|
      writes += 1
      raise IOError, 'Synthetic annual interruption' if writes == 2

      method.call(attributes)
    end
    expect { described_class.new(attempt).call }.to raise_error(IOError, /annual interruption/)
    record = DepartureDatasetNormalization.find_by!(status: 'running')
    expect([record.dataset_revision, record.rows.count]).to eq([nil, 0])
    allow(Departures::EvidenceRows).to receive(:annual).and_call_original
    completed = described_class.new(attempt).call
    expect(completed.status).to eq('completed')
    expect(Departures::DatasetStream.new(completed).expand)
      .to eq(Departures::AnnualDataset.new(manifest: attempt.manifest, directory:).call)
  end

  it 'retains only immutable scalar source references between source batches' do
    attempt = stored_attempt
    sources = described_class.new(attempt).parsed_sources
    expect(sources.values).to all(be_a(DepartureSourceNormalization::Reference))
    expect(sources.values).to all(be_frozen)
    expect(sources.values.map(&:status)).to all(eq('completed'))
    expect(expanded(attempt)).to eq(Departures::AnnualDataset.new(manifest: attempt.manifest, directory:).call)
  end

  context 'with malformed source routing identities' do
    cases = [
      ['missing player team ID', 1, 'teamId', :missing],
      ['null player team ID', 1, 'teamId', nil],
      ['null team ID', 3, 'teamId', nil],
      ['missing team ID', 3, 'teamId', :missing],
      ['numeric-string player team ID', 1, 'teamId', '20'],
      ['numeric-string team ID', 3, 'teamId', '20'],
      ['zero team ID', 1, 'teamId', 0],
      ['fractional team ID', 3, 'teamId', 20.5],
      ['invalid player team ID', 1, 'teamId', 'invalid'],
      ['null athlete ID', 1, 'athleteId', nil],
      ['missing athlete ID', 1, 'athleteId', :missing],
      ['numeric-string athlete ID', 1, 'athleteId', '10']
    ]
    %w[cbbd-draft-season-totals-v1 cbbd-draft-season-totals-v4].each do |version|
      cases.each do |label, index, key, value|
        it "preserves #{version} global failure and raw evidence for #{label}" do
          plan['extraction_version'] = version
          if version == 'cbbd-draft-season-totals-v4'
            plan.merge!('scope_evidence' => { 'policy' => Departures::DraftTeamSnapshot::POLICY },
                        'draft_policy' => 'confirmed_retained_results',
                        'team_matches' => [{ 'provider_team_id' => 20, 'team_id' => 1 }])
          end
          malformed = rows[index].first.deep_dup
          value == :missing ? malformed.delete(key) : malformed[key] = value
          rows[index] << malformed
          attempt = stored_attempt
          expected = Departures::AnnualDataset.new(manifest: attempt.manifest, directory:).call
          actual = expanded(attempt)
          expect(actual).to eq(expected)
          expect(actual.fetch('production')).to eq([])
          expect(actual.fetch('failures')).not_to be_empty
          source_id = index == 1 ? 'player-regular' : 'team-regular'
          expect(JSON.parse(Departures::RetainedEvidence.new(attempt).bytes(source_id))).to include(malformed)
        end
      end
    end
  end

  context 'with expected draft pick coverage' do
    [[[1, 59], 'completed'], [[59, 1], 'completed'], [[1, 2], 'incomplete'], [[1], 'incomplete'],
     [[1, 59, 60], 'incomplete']].each do |expected, status|
      it "requires exact picks #{expected.inspect}, independent of count and ordering" do
        plan['expected_picks'] = expected
        attempt = stored_attempt
        result = Departures::RetainedEvidence.new(attempt).acquisition_result
        legacy = Departures::AnnualDataset.new(manifest: attempt.manifest, directory:).call
        expect(result.fetch(:status)).to eq(status)
        expect(result.fetch(:status)).to eq(Departures::BatchAcquisition.result_status(legacy))
        expect(result.fetch(:dataset).fetch('summary').fetch('selections')).to eq(2)
      end
    end
  end
end
