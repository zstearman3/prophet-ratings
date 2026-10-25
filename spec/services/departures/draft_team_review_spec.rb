# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Departures::DraftTeamReview do
  let(:season) { create(:season, year: 2026) }
  let(:prior) { create(:season, year: 2025) }
  let(:team) { create(:team, school: 'Tracked College') }
  let(:new_team) { create(:team, school: 'New College') }
  let(:batch) { Departures::CapturePreparation.create(season, {}) }
  let(:picks) do
    [{ 'year' => 2025, 'overall' => 1, 'round' => 1, 'pick' => 1, 'name' => 'College Player',
       'athleteId' => 10, 'sourceTeamCollegeId' => 20 },
     { 'year' => 2025, 'overall' => 2, 'round' => 1, 'pick' => 2, 'name' => 'International Player',
       'athleteId' => nil, 'sourceTeamCollegeId' => nil, 'sourceTeamLocation' => 'International Club' },
     { 'year' => 2025, 'overall' => 3, 'round' => 1, 'pick' => 3, 'name' => 'New Team Player',
       'athleteId' => 30, 'sourceTeamCollegeId' => 30 }]
  end
  let(:players) do
    [{ 'season' => 2025, 'athleteId' => 10, 'teamId' => 20, 'team' => 'Source College', 'name' => 'College Player',
       'points' => 100, 'games' => 2, 'minutes' => 30 }]
  end
  let(:teams) do
    [{ 'season' => 2025, 'teamId' => 20, 'team' => 'Source College', 'games' => 2, 'totalMinutes' => 80,
       'teamStats' => { 'points' => { 'total' => 102 } } }]
  end
  let(:post_players) { [] }
  let(:post_teams) { [] }
  let(:post_status) { 200 }

  before do
    create(:team_season, season:, team:)
    create(:team_season, season: prior, team:)
    create(:team_season, season:, team: new_team)
    TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id: '20')
    TeamExternalIdentity.associate!(team: new_team, provider: 'cbbd', external_id: '30')
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('CBBD_API_KEY', '').and_return('synthetic-key')
    allow(Ingestion::Cbbd::HttpTransport).to receive(:call) do |uri, _key|
      post = URI.decode_www_form(uri.query).to_h['seasonType'] == 'postseason'
      rows = case uri.path
             when '/draft/picks' then picks
             when '/stats/player/season' then post ? post_players : players
             when '/stats/team/season' then post ? post_teams : teams
             end
      { status: post ? post_status : 200, body: JSON.generate(rows), headers: {} }
    end
  end

  def captured
    attempt = batch.attempt
    AcquireDepartureBatchJob.perform_now(attempt.id)
    attempt.reload
  end

  def review
    described_class.new(batch)
  end

  def approve(service = review)
    service.publish({ 'review_key' => service.report.fetch('review_key'), 'confirm' => '1' }, reviewer: 'admin')
  end

  it 'proposes only prior-season matched colleges and skips other players without global uncertainty or writes' do
    original = captured
    before = original.attributes.deep_dup
    expect { review.report }.not_to change(DepartureAcquisition, :count)
    result = review.report
    expect(result.fetch('players').pluck('status')).to eq(%w[included skipped skipped])
    expect(result.fetch('teams').find { |row| row['team_id'] == team.id }).to include('loss_share' => 100.0 / 102)
    expect(original.reload.attributes).to eq(before)
    expect(Ingestion::Cbbd::HttpTransport).to have_received(:call).exactly(5).times
  end

  it 'publishes one immutable successor and deterministic decisions after only the final confirmation' do
    original = captured
    before = original.attributes.deep_dup
    revision = approve
    frozen = ProphetRatings::DepartureContributionEvidence.capture(revision)
    expect(batch.reload.attempt).to have_attributes(predecessor_id: original.id, evidence: original.evidence)
    expect(batch.attempt.plan.fetch('extraction_version')).to eq('cbbd-draft-season-totals-v4')
    expect(original.reload.attributes).to eq(before)
    expect(revision.team_input(team.id)).to include('known_points_subtotal' => 100, 'team_points' => 102, 'loss_share' => 100.0 / 102)
    expect(ProphetRatings::DepartureContributionEvidence.new(frozen, new_team.id, 2026).call.fetch('loss_share')).to eq(0.0)
  end

  it 'rejects missing confirmation and stale prior-season membership before creating a successor' do
    original = captured
    service = review
    key = service.report.fetch('review_key')
    expect { service.publish({ 'review_key' => key }, reviewer: 'admin') }.to raise_error(ArgumentError, /Confirm/)
    prior.team_seasons.find_by!(team:).destroy!
    expect { review.publish({ 'review_key' => key, 'confirm' => '1' }, reviewer: 'admin') }.to raise_error(ArgumentError, /changed/)
    expect(batch.reload.attempt.id).to eq(original.id)
  end

  it 'keeps published rows frozen and retries publication idempotently after mapping changes' do
    captured
    revision = approve
    displayed = review.report
    TeamExternalIdentity.where(provider: 'cbbd', external_id: '20').destroy_all
    expect(review.report).to eq(displayed)
    expect(approve).to eq(revision)
    expect(OffseasonInputRevision.count).to eq(1)
  end

  it 'retains manually prepared v1 drafts and old published v2 revisions on their existing UI path' do
    fields = Departures::PreparationForm.defaults(2026).merge('expected_picks' => '1', 'scope_evidence' => 'Explicit final scope')
    manual = Departures::BatchPreparation.create(season, fields)
    expect(described_class.applicable?(manual)).to be(false)
    expect(described_class.applicable?(batch)).to be(true)
  end

  context 'with a missing draft athlete ID' do
    before { picks.first['athleteId'] = nil }

    it 'proposes a unique exact name only inside the draft source college and retains the original null' do
      captured
      player = review.report.fetch('players').first
      expect(player).to include('provider_athlete_id' => nil, 'matched_provider_athlete_id' => 10,
                                'match_method' => 'exact_name_within_college', 'status' => 'included')
      revision = approve
      stored = revision.payload.fetch('report').fetch('selections').first
      expect(stored.fetch('source_row')['athleteId']).to be_nil
      expect(stored).to include('draft_provider_athlete_id' => nil, 'provider_athlete_id' => 10)
      expect(revision.team_input(team.id).fetch('loss_share')).to eq(100.0 / 102)
    end

    it 'keeps ambiguous names unknown only for the tracked college' do
      players << players.first.merge('athleteId' => 11)
      captured
      result = review.report
      expect(result.fetch('players').first.fetch('status')).to eq('unknown_production')
      expect(result.fetch('teams').find { |row| row['team_id'] == team.id }.fetch('loss_share')).to be_nil
      expect(result.fetch('teams').find { |row| row['team_id'] == new_team.id }.fetch('loss_share')).to eq(0.0)
    end
  end

  context 'with a contradictory nonnull draft athlete ID' do
    before { picks.first['athleteId'] = 999 }

    it 'does not substitute the same-name stat identity and keeps uncertainty local' do
      captured
      player = review.report.fetch('players').first
      expect(player).to include('matched_provider_athlete_id' => 999, 'status' => 'unknown_production')
      expect(review.report.fetch('teams').find { |row| row['team_id'] == new_team.id }.fetch('loss_share')).to eq(0.0)
    end
  end

  context 'with null tracked-player points' do
    before { players.first['points'] = nil }

    it 'publishes a displayed team-local unknown without requiring a gap checkbox' do
      captured
      expect(review.report.fetch('players').first.fetch('status')).to eq('unknown_production')
      revision = approve
      expect(revision.team_input(team.id).fetch('loss_share')).to be_nil
      expect(revision.team_input(new_team.id).fetch('loss_share')).to eq(0.0)
    end
  end

  context 'with failed postseason responses' do
    let(:post_status) { 404 }

    it 'does not treat failed source responses as successful absence' do
      original = captured
      expect(review.report.fetch('errors')).not_to be_empty
      expect { approve }.to raise_error(ArgumentError, /source|CBBD/)
      expect(batch.reload.attempt.id).to eq(original.id)
    end
  end

  context 'with a postseason player missing while team production exists' do
    let(:post_players) { [players.first.merge('athleteId' => 11, 'name' => 'Other Player', 'points' => 10)] }
    let(:post_teams) { [teams.first.deep_merge('teamStats' => { 'points' => { 'total' => 10 } })] }

    it 'uses observed regular points and the full team total when no postseason player row exists' do
      captured
      expect(review.report.fetch('players').first.fetch('status')).to eq('included')
      revision = approve
      expect(revision.team_input(team.id)).to include('known_points_subtotal' => 100, 'team_points' => 112,
                                                      'loss_share' => 100.0 / 112)
      frozen = ProphetRatings::DepartureContributionEvidence.capture(revision)
      expect(ProphetRatings::DepartureContributionEvidence.new(frozen, team.id, 2026).call.fetch('loss_share')).to eq(100.0 / 112)
      player = revision.payload.fetch('dataset').fetch('production').first.fetch('players').find { |row| row['provider_athlete_id'] == 10 }
      expect(player.fetch('scope_rows').keys).to eq(['regular'])
    end

    it 'uses regular player points when no postseason player rows exist for the college' do
      post_players.clear
      captured
      expect(review.report.fetch('players').first.fetch('status')).to eq('included')
      expect(approve.team_input(team.id)).to include('known_points_subtotal' => 100, 'team_points' => 112,
                                                     'loss_share' => 100.0 / 112)
    end

    it 'preserves the earlier v3 interpretation of missing postseason participation' do
      captured
      proposal = Departures::DraftTeamSnapshot.new(batch, batch.attempt).proposed_attempt
      proposal.plan = proposal.plan.merge('extraction_version' => 'cbbd-draft-season-totals-v3')
      proposal.manifest = proposal.manifest.merge('extraction_version' => 'cbbd-draft-season-totals-v3')
      dataset = Departures::RetainedEvidence.new(proposal).dataset
      player = dataset.fetch('production').first.fetch('players').find { |row| row['provider_athlete_id'] == 10 }
      expect(player.fetch('coverage_complete')).to be(false)
    end

    it 'keeps explicit null postseason player points unknown' do
      post_players << players.first.merge('points' => nil)
      captured
      expect(review.report.fetch('players').first.fetch('status')).to eq('unknown_production')
      expect(approve.team_input(team.id).fetch('loss_share')).to be_nil
    end

    it 'does not infer missing regular-season player production from a postseason appearance' do
      players.first['athleteId'] = 99
      post_players.first.merge!('athleteId' => 10, 'name' => 'College Player')
      captured
      expect(review.report.fetch('players').first.fetch('status')).to eq('unknown_production')
      expect(approve.team_input(team.id).fetch('loss_share')).to be_nil
    end
  end

  it 'keeps a transfer player unknown only for the college with missing points' do
    second = create(:team, school: 'Second College')
    create(:team_season, season:, team: second)
    create(:team_season, season: prior, team: second)
    TeamExternalIdentity.associate!(team: second, provider: 'cbbd', external_id: '40')
    players << players.first.merge('teamId' => 40, 'team' => 'Second College', 'points' => nil)
    teams << teams.first.deep_merge('teamId' => 40, 'team' => 'Second College', 'teamStats' => { 'points' => { 'total' => 80 } })
    captured
    colleges = review.report.fetch('players').first.fetch('college_teams')
    expect(colleges.pluck('status')).to contain_exactly('included', 'unknown_production')
    revision = approve
    expect(revision.team_input(team.id).fetch('loss_share')).to eq(100.0 / 102)
    expect(revision.team_input(second.id).fetch('loss_share')).to be_nil
    frozen = ProphetRatings::DepartureContributionEvidence.capture(revision)
    expect(ProphetRatings::DepartureContributionEvidence.new(frozen, second.id, 2026).call.fetch('loss_share')).to be_nil
  end

  it 'uses known drafted points when an undrafted teammate has null points' do
    players << players.first.merge('athleteId' => 11, 'name' => 'Undrafted Player', 'points' => nil)
    captured
    expect(approve.team_input(team.id).fetch('loss_share')).to eq(100.0 / 102)
  end

  it 'does not change captured legacy v2 evidence by adding the new automatic scope fields' do
    dataset = { 'schema' => 'draft-departures-v2', 'provider' => 'cbbd', 'extraction_version' => 'cbbd-draft-season-totals-v2',
                'scope_evidence' => 'Original human scope note', 'expected_picks' => [1], 'failures' => [], 'sources' => [] }
    frozen = ProphetRatings::DepartureContributionEvidence.captured_dataset('dataset' => dataset)
    expect(frozen.keys).to contain_exactly('schema', 'provider', 'extraction_version', 'expected_picks', 'failures', 'sources')
  end

  it 'shows unknown college production for a player with no recorded participation' do
    players.first['games'] = 0
    captured
    player = review.report.fetch('players').first
    expect(player.fetch('status')).to eq('unknown_production')
    expect(player.fetch('college_teams').first).to include('loss_share' => nil, 'status' => 'unknown_production')
  end
end
