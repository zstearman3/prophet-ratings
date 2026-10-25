# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Departures::BatchReview do
  let(:season) { create(:season, year: 2026) }
  let(:team) { create(:team, school: 'Renamed School') }
  let(:fields) do
    { 'draft_year' => '2025', 'prior_season_year' => '2025', 'target_year' => '2026', 'expected_picks' => '1 59',
      'scope_evidence' => 'Reviewed final regular and postseason totals', 'max_requests' => '5', 'retries' => '0' }
  end
  let(:batch) { Departures::BatchPreparation.create(season, fields) }
  let(:fixture_options) { {} }
  let(:picks) do
    [10, 12].zip([1, 59]).map do |athlete, pick|
      { 'year' => 2025, 'overall' => pick, 'round' => pick == 1 ? 1 : 2, 'pick' => pick == 1 ? 1 : 29,
        'name' => "Player #{athlete}", 'athleteId' => athlete, 'sourceTeamCollegeId' => 20, 'sourceTeamLocation' => 'Old School' }
    end
  end

  before do
    create(:team_season, season:, team:)
    TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: '20')
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('CBBD_API_KEY', '').and_return('synthetic-key')
    allow(Ingestion::Cbbd::HttpTransport).to receive(:call) do |uri, _key|
      query = URI.decode_www_form(uri.query).to_h
      post = query['seasonType'] == 'postseason'
      payload = case uri.path
                when '/draft/picks' then picks
                when '/stats/player/season'
                  scope_players(post) + transfer_players(post)
                when '/stats/team/season' then [{ 'season' => 2025, 'teamId' => 20, 'team' => 'Old School', 'games' => 8,
                                                  'totalMinutes' => 320,
                                                  'teamStats' => { 'points' => { 'total' => post ? 400 : 1600 } } }] + transfer_teams(post)
                end
      { status: 200, body: JSON.generate(payload), headers: {} }
    end
  end

  def player(id, points)
    { 'season' => 2025, 'athleteId' => id, 'athleteSourceId' => "upstream-#{id}", 'name' => "Player #{id}",
      'teamId' => 20, 'team' => 'Old School', 'points' => points, 'games' => 8, 'minutes' => 20.5 }
  end

  def scope_players(post)
    generated = [player(10, post ? 100 : 400), player(11, post ? 300 : 1200), player(12, 0)]
    if fixture_options[:overflow_scope] == (post ? 'postseason' : 'regular')
      generated[0]['points'] = post ? 500 : 1700
      generated[1]['points'] = nil
    end
    generated
  end

  def transfer_players(post)
    return [] unless fixture_options[:transfer]

    [player(10, post ? 10 : 40), player(11, post ? 30 : 120)].map do |row|
      row.merge('teamId' => 30, 'team' => 'Second School')
    end
  end

  def transfer_teams(post)
    return [] unless fixture_options[:transfer]

    [{ 'season' => 2025, 'teamId' => 30, 'team' => 'Second School', 'games' => 8,
       'totalMinutes' => 320, 'teamStats' => { 'points' => { 'total' => post ? 40 : 160 } } }]
  end

  def capture
    attempt = Departures::BatchPreparation.new(batch).acquire
    AcquireDepartureBatchJob.perform_now(attempt.id)
    attempt.reload
  end

  def rows
    [10, 12].zip([1, 59]).to_h do |athlete, pick|
      ["2025/#{pick}", { 'status' => 'eligible_prior_season', 'reason' => 'Reviewed exact provider athlete identity',
                         'evidence_source_ids' => %w[draft player-regular player-postseason team-regular team-postseason],
                         'stints' => { '0' => { 'production_key' => "cbbd/team/20|cbbd/athlete/#{athlete}", 'team_id' => team.id.to_s,
                                                'identity_evidence_source_ids' => %w[draft player-regular player-postseason] } } }]
    end
  end

  it 'acquires JSON once and publishes .25 from exact mapped IDs with zero-point participation and offline scoring' do
    attempt = capture
    expect(attempt.status).to eq('completed')
    AcquireDepartureBatchJob.perform_now(attempt.id)
    expect(Ingestion::Cbbd::HttpTransport).to have_received(:call).exactly(5).times
    review = described_class.new(batch)
    review.save('review_key' => review.review_key, 'rows' => rows)
    revision = review.publish({ 'review_key' => review.review_key, 'confirm' => '1' }, reviewer: 'admin@example.com')
    captured = ProphetRatings::DepartureContributionEvidence.capture(revision)
    expect(captured.slice('schema', 'provider', 'extraction_version')).to eq(
      'schema' => 'draft-departures-v2', 'provider' => 'cbbd', 'extraction_version' => 'cbbd-draft-season-totals-v1'
    )
    expect(ProphetRatings::DepartureContributionEvidence.new(captured, team.id, 2026).call['loss_share']).to eq(0.25)
    expect(Ingestion::Cbbd::HttpTransport).to have_received(:call).exactly(5).times
  end

  it 'rejects a different provider athlete on the selected production row' do
    capture
    altered = rows
    altered['2025/1']['stints']['0']['production_key'] = 'cbbd/team/20|cbbd/athlete/11'
    review = described_class.new(batch)
    review.save('review_key' => review.review_key, 'rows' => altered)
    expect(review.report['errors'].join).to include('athlete')
  end

  it 'makes provider mapping changes invalidate a displayed review' do
    capture
    review = described_class.new(batch)
    key = review.review_key
    TeamExternalIdentity.where(provider: 'cbbd', external_id: '20').delete_all
    expect { review.save('review_key' => key, 'rows' => rows) }.to raise_error(ArgumentError, /changed/)
  end

  it 'does not start another client for duplicate running job delivery' do
    attempt = Departures::BatchPreparation.new(batch).acquire
    attempt.update!(status: 'running', started_at: Time.current)
    AcquireDepartureBatchJob.perform_now(attempt.id)
    expect(attempt.reload.status).to eq('running')
    expect(Ingestion::Cbbd::HttpTransport).not_to have_received(:call)
  end

  it 'rejects provider rows when their v2 scoring discriminator is removed' do
    capture
    review = described_class.new(batch)
    review.save('review_key' => review.review_key, 'rows' => rows)
    revision = review.publish({ 'review_key' => review.review_key, 'confirm' => '1' }, reviewer: 'admin')
    evidence = ProphetRatings::DepartureContributionEvidence.capture(revision).except('schema', 'provider', 'extraction_version')
    expect { ProphetRatings::DepartureContributionEvidence.new(evidence, team.id, 2026).call }
      .to raise_error(ArgumentError, /contract|identity/)
  end

  it 'revalidates retained retry bytes and refuses approval after corruption' do
    attempt = capture
    review = described_class.new(batch)
    review.save('review_key' => review.review_key, 'rows' => rows)
    observation = DepartureCaptureObservation.find(attempt.evidence.fetch('observations').fetch('capture-1'))
    corrupt_departure_capture(observation.departure_source_capture_id, 'changed')
    allow(batch).to receive(:attempt).and_return(attempt)
    expect { review.publish({ 'review_key' => review.review_key, 'confirm' => '1' }, reviewer: 'admin') }
      .to raise_error(ArgumentError, /hash|identity mismatch/)
    expect(OffseasonInputRevision.count).to eq(0)
  end

  it 'requires explicit interruption confirmation before retaining a new bounded successor' do
    first = Departures::BatchPreparation.new(batch).acquire
    first.update!(status: 'running', started_at: Time.current)
    expect { Departures::BatchPreparation.new(batch).acquire }.to raise_error(ArgumentError, /Wait/)
    successor = Departures::BatchPreparation.new(batch).acquire('close_interrupted' => '1')
    expect(first.reload.status).to eq('failed')
    expect(successor.predecessor_id).to eq(first.id)
    expect(successor.status).to eq('queued')
  end

  it 'requires all exact athlete stints and publishes each team with its independent denominator' do
    fixture_options[:transfer] = true
    second = create(:team, school: 'Second School')
    create(:team_season, season:, team: second)
    TeamExternalIdentity.associate!(team: second, provider: 'cbbd', external_id: '30')
    capture
    review = described_class.new(batch)
    review.save('review_key' => review.review_key, 'rows' => rows)
    expect(review.report['errors'].join).to include('all evidenced')
    complete = rows
    complete['2025/1']['stints']['1'] = complete['2025/1']['stints']['0'].merge(
      'production_key' => 'cbbd/team/30|cbbd/athlete/10', 'team_id' => second.id.to_s
    )
    allow(Departures::DecisionForm).to receive(:table_choices).and_call_original
    review.save('review_key' => review.review_key, 'rows' => complete)
    expect(Departures::DecisionForm).to have_received(:table_choices).exactly(2).times
    revision = review.publish({ 'review_key' => review.review_key, 'confirm' => '1' }, reviewer: 'admin')
    expect(revision.team_input(team.id)).to include('team_points' => 2000, 'known_points_subtotal' => 500, 'loss_share' => 0.25)
    expect(revision.team_input(second.id)).to include('team_points' => 200, 'known_points_subtotal' => 50, 'loss_share' => 0.25)
  end

  it 'keeps null draft identity unknown and refuses to infer a verified exclusion from affiliation' do
    picks.first['athleteId'] = nil
    capture
    unknown = rows
    unknown['2025/1'] =
      { 'status' => 'unknown_participation', 'reason' => 'Provider identity is missing', 'evidence_source_ids' => ['draft'] }
    review = described_class.new(batch)
    review.save('review_key' => review.review_key, 'rows' => unknown)
    expect(review.report['teams'].pluck('loss_share')).to all(be_nil)
    unknown['2025/1']['status'] = 'verified_no_college'
    review.save('review_key' => review.review_key, 'rows' => unknown)
    expect(review.report['errors'].join).to include('does not prove')
  end

  it 'keeps every captured stint in the uncertainty accounting and does not localize a null athlete identity' do
    fixture_options[:transfer] = true
    second = create(:team)
    unaffected = create(:team)
    TeamExternalIdentity.associate!(team: second, provider: 'cbbd', external_id: '30')
    capture
    unknown = rows
    unknown['2025/1'] = { 'status' => 'unknown_production', 'reason' => 'Unestablished production', 'evidence_source_ids' => ['draft'] }
    review = described_class.new(batch)
    review.save('review_key' => review.review_key, 'rows' => unknown)
    expect(review.report.fetch('selections').first.fetch('candidate_team_ids')).to contain_exactly(team.id, second.id)
    expect(review.report.fetch('teams').find { |row| row['team_id'] == unaffected.id }['loss_share']).to eq(0.0)
    TeamExternalIdentity.where(provider: 'cbbd', external_id: '30').destroy_all
    expect(review.report.fetch('selections').first.fetch('candidate_team_ids')).to eq([])
  end

  %w[regular postseason].each do |scope|
    it "cannot acknowledge away a definite #{scope} points conflict hidden beside unknown points" do
      fixture_options[:overflow_scope] = scope
      capture
      decisions = rows.transform_values do |row|
        row.except('stints').merge('status' => 'unknown_production', 'reason' => 'Missing points acknowledged')
      end
      review = described_class.new(batch)
      review.save('review_key' => review.review_key, 'rows' => decisions)
      expect do
        review.publish({ 'review_key' => review.review_key, 'confirm' => '1', 'acknowledge_gaps' => '1' }, reviewer: 'admin')
      end.to raise_error(ArgumentError, /failed departure sources/)
      expect([OffseasonInputRevision.count, TeamOffseasonProfile.count, batch.reload.reviewed_by]).to eq([0, 0, nil])
    end
  end
end
