# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Departures::CoverageReview do
  let(:season) { create(:season, year: 2026) }
  let(:team) { create(:team, school: 'Local School') }
  let(:batch) { Departures::CapturePreparation.create(season, {}) }
  let(:picks) do
    [{ 'year' => 2025, 'overall' => 1, 'round' => 1, 'pick' => 1, 'name' => 'First Player',
       'athleteId' => 10, 'sourceTeamCollegeId' => 20 }]
  end
  let(:regular_players) do
    [{ 'season' => 2025, 'athleteId' => 10, 'teamId' => 20, 'team' => 'Source School', 'name' => 'First Player',
       'points' => 100, 'games' => 2, 'minutes' => 30 }]
  end
  let(:regular_teams) do
    [{ 'season' => 2025, 'teamId' => 20, 'team' => 'Source School', 'games' => 2, 'totalMinutes' => 80,
       'teamStats' => { 'points' => { 'total' => 100 } } }]
  end
  let(:post_players) { [] }
  let(:post_teams) { [] }
  let(:post_status) { 200 }
  let(:coverage) { described_class.new(batch) }

  before do
    create(:team_season, season:, team:)
    TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: '20')
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('CBBD_API_KEY', '').and_return('synthetic-key')
    allow(Ingestion::Cbbd::HttpTransport).to receive(:call) do |uri, _key|
      postseason = URI.decode_www_form(uri.query).to_h['seasonType'] == 'postseason'
      payload = case uri.path
                when '/draft/picks' then picks
                when '/stats/player/season' then postseason ? post_players : regular_players
                when '/stats/team/season' then postseason ? post_teams : regular_teams
                end
      { status: postseason ? post_status : 200, body: JSON.generate(payload), headers: {} }
    end
  end

  def capture
    attempt = batch.attempt
    AcquireDepartureBatchJob.perform_now(attempt.id)
    attempt.reload
  end

  def fields
    { 'review_key' => coverage.report.fetch('review_key'), 'expected_picks' => '1 59',
      'confirm_picks' => '1', 'picks_evidence' => 'Independent final draft results, including final pick 59',
      'confirm_scope' => '1', 'scope_evidence' => 'Final completed regular and postseason season totals',
      'absent_postseason_team_ids' => ['20'] }
  end

  it 'derives capture years and queues bounded capture without coverage assertions' do
    expect(batch.plan).to include('draft_year' => 2025, 'prior_season_year' => 2025, 'target_year' => 2026,
                                  'max_requests' => 15, 'retries' => 2)
    expect(batch.plan).not_to have_key('expected_picks')
    expect(batch.attempt.status).to eq('queued')
    expect { Departures::CbbdDataset.validate_plan(batch.plan) }.to raise_error(ArgumentError)
  end

  it 'retains terminal raw capture without exposing an annual dataset or permitting publication' do
    attempt = capture
    expect(attempt).to have_attributes(status: 'completed', dataset: {})
    expect(attempt.evidence.fetch('storage_version')).to eq(Departures::CaptureStore::VERSION)
    ids = %w[draft player-regular team-regular player-postseason team-postseason capture-1 capture-2 capture-3 capture-4 capture-5]
    expect(attempt.evidence.fetch('observations').keys).to match_array(ids)
    review = Departures::BatchReview.new(batch)
    expect { review.save('review_key' => review.review_key, 'rows' => {}) }.to raise_error(ArgumentError, /Acquire/)
    expect { review.publish({ 'review_key' => review.review_key, 'confirm' => '1' }, reviewer: 'admin') }
      .to raise_error(ArgumentError, /Acquire/)
  end

  it 'rejects altered years, source requests and out-of-bounds request limits before capture' do
    expect { Departures::CapturePreparation.create(season, 'draft_year' => '2024') }.to raise_error(ArgumentError, /year/i)
    expect { Departures::CapturePreparation.create(season, 'sources' => [{ 'id' => 'foreign' }]) }
      .to raise_error(ArgumentError, /source/i)
    [0, 101].each do |limit|
      expect { Departures::CapturePreparation.create(season, 'max_requests' => limit) }.to raise_error(ArgumentError)
    end
    expect { Departures::CapturePreparation.create(season, 'retries' => 6) }.to raise_error(ArgumentError, /retries/)
    expect(Ingestion::Cbbd::HttpTransport).not_to have_received(:call)
  end

  it 'requires explicit confirmation before replacing an interrupted capture' do
    first = batch.attempt
    first.update!(status: 'running', started_at: Time.current)
    expect { Departures::CapturePreparation.new(batch).acquire }.to raise_error(ArgumentError, /Wait/)
    successor = Departures::CapturePreparation.new(batch).acquire('close_interrupted' => '1')
    expect(first.reload.status).to eq('failed')
    expect(successor.predecessor_id).to eq(first.id)
    expect(successor.status).to eq('queued')
  end

  it 'presents observed selections as unconfirmed and offers named legitimate no-postseason candidates unchecked' do
    capture
    report = coverage.report
    expect(report.fetch('selections').pluck('overall_pick')).to eq([1])
    expect(report.fetch('fields')).to include('expected_picks' => '', 'confirm_picks' => '',
                                              'confirm_scope' => '', 'absent_postseason_team_ids' => [])
    expect(report.fetch('no_postseason_teams')).to eq(
      [{ 'provider_team_id' => 20, 'team_name_source' => 'Source School', 'team_id' => team.id, 'team_name' => 'Local School' }]
    )
    expect(report.fetch('sources').size).to eq(5)
    expect(report.fetch('errors')).to eq([])
  end

  it 'creates an offline immutable strict-v2 successor with authenticated provenance and missing trailing picks' do
    original = capture
    batch.update!(decisions: [{ 'old' => true }], acknowledgement: { 'old' => true })
    submitted = fields.merge('reviewed_by' => 'forged', 'max_requests' => 100, 'target_year' => 2040)
    successor = coverage.save(submitted, reviewer: 'signed-in-admin')
    expect(successor).to have_attributes(status: 'incomplete', predecessor_id: original.id)
    expect(successor.plan).to include('schema' => 'draft-departures-v2', 'target_year' => 2026, 'max_requests' => 15,
                                      'expected_picks' => [1, 59])
    expect(successor.plan.fetch('coverage_review')).to include('reviewed_by' => 'signed-in-admin',
                                                               'predecessor_id' => original.id,
                                                               'picks_evidence' => submitted['picks_evidence'])
    expect(Departures::BatchReview.new(batch).report.fetch('teams').pluck('loss_share')).to all(be_nil)
  end

  it 'replays offline from unchanged predecessor bytes and ledgers' do
    original = capture
    original_attributes = original.attributes.deep_dup
    successor = coverage.save(fields, reviewer: 'admin')
    expect(original.reload.attributes).to eq(original_attributes)
    expect(successor.evidence).to eq(original.evidence)
    expect(successor.manifest.slice('sources', 'captures')).to eq(original.manifest.slice('sources', 'captures'))
    expect(Ingestion::Cbbd::HttpTransport).to have_received(:call).exactly(5).times
  end

  it 'never promotes observed picks or empty evidence into explicit coverage approval' do
    capture
    %w[confirm_picks picks_evidence confirm_scope scope_evidence].each do |key|
      expect { coverage.save(fields.merge(key => ''), reviewer: 'admin') }.to raise_error(ArgumentError)
    end
    expect { coverage.save(fields.merge('expected_picks' => ''), reviewer: 'admin') }.to raise_error(ArgumentError)
    expect { coverage.save(fields, reviewer: '') }.to raise_error(ArgumentError, /reviewer/)
    expect(batch.acquisitions.count).to eq(1)
  end

  it 'rejects stale coverage submissions and unrelated absence IDs' do
    capture
    stale = fields
    expect { coverage.save(fields.merge('absent_postseason_team_ids' => ['999']), reviewer: 'admin') }
      .to raise_error(ArgumentError, /postseason/)
    coverage.save(fields, reviewer: 'admin')
    expect { coverage.save(stale, reviewer: 'admin') }.to raise_error(ArgumentError, /changed/)
  end

  it 'revalidates every retained byte before creating an offline successor' do
    attempt = capture
    submitted = fields
    observation = DepartureCaptureObservation.find(attempt.evidence.fetch('observations').fetch('capture-1'))
    corrupt_departure_capture(observation.departure_source_capture_id, 'changed')
    allow(batch).to receive(:attempt).and_return(attempt)
    submitted['review_key'] = coverage.review_key
    expect { coverage.save(submitted, reviewer: 'admin') }.to raise_error(ArgumentError, /hash|identity mismatch/)
    expect(batch.acquisitions.count).to eq(1)
  end

  it 'rejects tampered source requests before making a capture client' do
    plan = batch.plan.deep_dup
    plan['sources'].first['request']['year'] = 2024
    Dir.mktmpdir('invalid-capture') do |directory|
      expect { Departures::CbbdAcquisition.new(plan:, directory:).call }.to raise_error(ArgumentError, /source/i)
    end
    expect(Ingestion::Cbbd::HttpTransport).not_to have_received(:call)
  end

  it 'makes incomplete acquisition states renderable without fetching' do
    expect(coverage.report.fetch('errors')).to include(/Acquire/)
    expect(Ingestion::Cbbd::HttpTransport).not_to have_received(:call)
  end

  it 'clears downstream decisions and approval when coverage changes on an existing strict-v2 batch' do
    capture
    first = coverage.save(fields, reviewer: 'first-admin')
    batch.update!(decisions: [{ 'old' => true }], acknowledgement: { 'old' => true }, reviewed_by: 'old-admin', reviewed_at: Time.current)
    second = coverage.save(fields, reviewer: 'second-admin')
    expect(second.predecessor_id).to eq(first.id)
    expect(batch.reload).to have_attributes(decisions: [], acknowledgement: {}, reviewed_by: nil, reviewed_at: nil)
    expect(second.plan.fetch('coverage_review')).to include('reviewed_by' => 'second-admin')
    expect(Ingestion::Cbbd::HttpTransport).to have_received(:call).exactly(5).times
  end

  context 'with malformed draft facts' do
    let(:picks) { [{ 'year' => 2024, 'overall' => 1, 'round' => 1, 'pick' => 1, 'name' => 'Wrong season' }] }

    it 'keeps invalid source facts blocking explicit coverage approval' do
      capture
      expect(coverage.report.fetch('errors')).to include(/Wrong draft year/)
      expect { coverage.save(fields, reviewer: 'admin') }.to raise_error(ArgumentError, /Wrong draft year/)
      expect(batch.acquisitions.count).to eq(1)
    end
  end

  context 'with malformed nested team statistics' do
    let(:regular_teams) { [super().first.merge('teamStats' => 'malformed')] }

    it 'returns blocking coverage errors and rejects saving without creating a successor' do
      expect(capture.status).to eq('completed')
      expect(coverage.report.fetch('errors')).to include(/dig/)
      expect { coverage.save(fields, reviewer: 'admin') }.to raise_error(ArgumentError, /dig/)
      expect(batch.acquisitions.count).to eq(1)
    end
  end

  context 'with a failed postseason source' do
    let(:post_status) { 404 }

    it 'keeps absence unknown and rejects a submitted no-postseason assertion' do
      capture
      expect(coverage.report.fetch('no_postseason_teams')).to eq([])
      expect { coverage.save(fields, reviewer: 'admin') }.to raise_error(ArgumentError, /postseason/)
      successor = coverage.save(fields.merge('absent_postseason_team_ids' => []), reviewer: 'admin')
      facts = Departures::RetainedEvidence.new(successor).dataset
      expect(facts.fetch('production').first.fetch('coverage_complete')).to be(false)
    end
  end

  context 'with postseason player production' do
    let(:post_players) { regular_players }

    it 'does not offer a team as absent when either postseason source contains its production' do
      capture
      expect(coverage.report.fetch('no_postseason_teams')).to eq([])
      expect { coverage.save(fields, reviewer: 'admin') }.to raise_error(ArgumentError, /postseason/)
    end
  end

  context 'with a discrepant full-roster subtotal' do
    let(:regular_teams) { [super().first.deep_merge('teamStats' => { 'points' => { 'total' => 102 } })] }

    it 'preserves captured picks and sources with informational reconciliation warnings' do
      capture
      current = coverage.report
      expect(current.fetch('errors')).to eq([])
      expect(current.fetch('selections').pluck('overall_pick')).to eq([1])
      expect(current.fetch('sources').size).to eq(5)
      expect(current.fetch('production_warnings')).to include(
        hash_including('provider_team_id' => 20, 'team_name_source' => 'Source School', 'scope' => 'regular',
                       'team_points' => 102, 'known_player_points_subtotal' => 100, 'difference' => -2)
      )
    end

    it 'reviews an existing raw capture offline under the new extraction and publishes the reported points ratio' do
      original = capture
      original_attributes = original.attributes.deep_dup
      successor = coverage.save(fields.merge('expected_picks' => '1'), reviewer: 'admin')
      review = Departures::BatchReview.new(batch)
      decision = { 'status' => 'eligible_prior_season', 'reason' => 'Reviewed exact provider identity',
                   'evidence_source_ids' => %w[draft player-regular team-regular],
                   'stints' => { '0' => { 'production_key' => 'cbbd/team/20|cbbd/athlete/10', 'team_id' => team.id.to_s,
                                          'identity_evidence_source_ids' => %w[draft player-regular team-regular] } } }
      review.save('review_key' => review.review_key, 'rows' => { '2025/1' => decision })
      revision = review.publish({ 'review_key' => review.review_key, 'confirm' => '1' }, reviewer: 'admin')
      frozen_evidence = ProphetRatings::DepartureContributionEvidence.capture(revision)
      expect(successor.plan).to include('extraction_version' => 'cbbd-draft-season-totals-v2')
      expect(original.reload.attributes).to eq(original_attributes)
      expect(revision.team_input(team.id)).to include('known_points_subtotal' => 100, 'team_points' => 102, 'loss_share' => 100.0 / 102)
      expect(ProphetRatings::DepartureContributionEvidence.new(frozen_evidence, team.id, 2026).call.fetch('loss_share')).to eq(100.0 / 102)
      expect(Ingestion::Cbbd::HttpTransport).to have_received(:call).exactly(5).times
    end

    it 'retains warnings in the saved report and frozen scoring evidence' do
      capture
      coverage.save(fields.merge('expected_picks' => '1'), reviewer: 'admin')
      review = Departures::BatchReview.new(batch)
      decisions = { '2025/1' => { 'status' => 'unknown_production', 'reason' => 'Pending player review',
                                  'evidence_source_ids' => ['draft'] } }
      review.save('review_key' => review.review_key, 'rows' => decisions)
      revision = review.publish({ 'review_key' => review.review_key, 'confirm' => '1', 'acknowledge_gaps' => '1' }, reviewer: 'admin')
      expected = [{ 'provider_team_id' => 20, 'team_name_source' => 'Source School', 'scope' => 'regular', 'team_points' => 102,
                    'known_player_points_subtotal' => 100, 'difference' => -2, 'all_player_points_known' => true,
                    'reason' => 'player_team_points_mismatch' }]
      expect(revision.payload.fetch('dataset').fetch('production_warnings')).to eq(expected)
      expect(revision.payload.fetch('report').fetch('production_warnings')).to eq(expected)
      expect(ProphetRatings::DepartureContributionEvidence.capture(revision).fetch('production_warnings')).to eq(expected)
    end
  end

  context 'with drafted points exceeding the independent denominator' do
    let(:regular_teams) { [super().first.deep_merge('teamStats' => { 'points' => { 'total' => 98 } })] }

    it 'retains the hard publication gate after coverage accepts the source warning' do
      capture
      coverage.save(fields.merge('expected_picks' => '1'), reviewer: 'admin')
      review = Departures::BatchReview.new(batch)
      decision = { 'status' => 'eligible_prior_season', 'reason' => 'Exact provider identity',
                   'evidence_source_ids' => %w[draft player-regular team-regular],
                   'stints' => { '0' => { 'production_key' => 'cbbd/team/20|cbbd/athlete/10', 'team_id' => team.id.to_s,
                                          'identity_evidence_source_ids' => %w[draft player-regular team-regular] } } }
      review.save('review_key' => review.review_key, 'rows' => { '2025/1' => decision })
      expect(review.report.fetch('errors')).to include(/Drafted points exceed/)
      expect { review.publish({ 'review_key' => review.review_key, 'confirm' => '1' }, reviewer: 'admin') }
        .to raise_error(ArgumentError, /Drafted points exceed/)
      expect(OffseasonInputRevision.count).to eq(0)
    end
  end

  context 'with invalid regular-season numeric facts' do
    let(:regular_players) { [super().first.merge('points' => -1)] }

    it 'retains safe pick and source context while blocking the invalid normalization' do
      capture
      current = coverage.report
      expect(current.fetch('selections').pluck('overall_pick')).to eq([1])
      expect(current.fetch('sources').size).to eq(5)
      expect(current.fetch('errors')).to include(/points/)
      expect { coverage.save(fields, reviewer: 'admin') }.to raise_error(ArgumentError, /points/)
      expect(batch.acquisitions.count).to eq(1)
    end
  end

  it 'invalidates displayed coverage when the proposed extraction policy changes' do
    capture
    submitted = fields
    stub_const('Departures::CbbdDataset::REPORTED_TOTALS_EXTRACTION', 'cbbd-draft-season-totals-future')
    expect { coverage.save(submitted, reviewer: 'admin') }.to raise_error(ArgumentError, /changed/)
    expect(batch.acquisitions.count).to eq(1)
  end

  it 'upgrades strict reviewed extraction only on an explicit offline coverage save' do
    strict_fields = { 'draft_year' => 2025, 'prior_season_year' => 2025, 'target_year' => 2026, 'expected_picks' => '1',
                      'scope_evidence' => 'Previously reviewed final totals', 'max_requests' => 5, 'retries' => 0,
                      'absent_postseason_team_ids' => '20' }
    strict_batch = Departures::BatchPreparation.create(season, strict_fields)
    original = Departures::BatchPreparation.new(strict_batch).acquire
    AcquireDepartureBatchJob.perform_now(original.id)
    original.reload
    original_attributes = original.attributes.deep_dup
    service = described_class.new(strict_batch)
    displayed = service.report
    expect(strict_batch.reload.plan.fetch('extraction_version')).to eq('cbbd-draft-season-totals-v1')
    expect(original.dataset).not_to have_key('production_warnings')
    submitted = displayed.fetch('fields').merge('review_key' => displayed.fetch('review_key'), 'confirm_picks' => '1',
                                                'confirm_scope' => '1', 'picks_evidence' => 'Independent final draft results')
    successor = service.save(submitted, reviewer: 'admin')
    expect(successor.plan.fetch('extraction_version')).to eq('cbbd-draft-season-totals-v2')
    expect(original.reload.attributes).to eq(original_attributes)
    expect(Ingestion::Cbbd::HttpTransport).to have_received(:call).exactly(5).times
  end
end
