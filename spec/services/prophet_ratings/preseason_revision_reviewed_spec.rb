# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::PreseasonRevision do
  include ActiveSupport::Testing::TimeHelpers

  let(:season) { create(:season, year: 2027, start_date: Date.new(2026, 11, 1), end_date: Date.new(2027, 4, 10)) }
  let(:previous) do
    create(:season, year: 2026, start_date: Date.new(2025, 11, 1), end_date: Date.new(2026, 4, 10),
                    average_efficiency: 100, average_pace: 70)
  end
  let!(:home) { create(:team_season, season:) }
  let!(:away) { create(:team_season, season:) }
  let(:config) do
    RatingsConfigVersion.authored_config.merge(bundle_name: 'reviewed-r3').tap do |payload|
      payload[:preseason].merge!(YAML.load_file(Rails.root.join('config/examples/reviewed_efficiency_r3.yml')).deep_symbolize_keys)
    end
  end
  let(:version) { RatingsConfigVersion.publish!(config) }
  let(:operation) { described_class.new(season, ratings_config_version: version) }
  let(:recruiting) do
    { 'status' => 'verified_points', 'class_points' => '70',
      'units' => { 'class_points' => '247_recruit_composite_class_points' },
      'row' => { 'raw_label' => 'Synthetic College', 'source_url' => 'https://school.example/class' } }
  end

  before do
    create(:team_season, season: previous, team: home.team, adj_offensive_efficiency: 100, adj_defensive_efficiency: 100, adj_pace: 68)
    travel_to((season.start_date - 1.day).in_time_zone + 12.hours)
  end

  def revision(points = '70')
    review = { 'review_status' => 'reviewed', 'approval' => { 'approved_by' => 'Test operator', 'approved_at' => Time.current.iso8601 } }
    payload = { 'kind' => 'recruiting', 'dataset_hash' => 'a' * 64, 'review_hash' => Departures::Contract.digest(review),
                'review' => review, 'team_inputs' => { home.team_id.to_s => recruiting.merge('class_points' => points) } }
    OffseasonInputRevision.create!(season:, kind: 'recruiting', version: "synthetic-#{points}", reason: 'Synthetic test review',
                                   input_hash: Departures::Contract.digest(payload), dataset_hash: payload.fetch('dataset_hash'),
                                   review_hash: payload.fetch('review_hash'), payload:)
  end

  def profile
    @profile ||= create(:team_offseason_profile, team_season: home, recruiting_revision: revision,
                                                 recruiting_score: nil, returning_minutes_pct: nil, manual_adjustment: nil)
  end

  def publish
    operation.call(preview_key: operation.preview.fetch(:preview_key))
  end

  def forecast(selected)
    game = create(:game, season:, status: :scheduled, start_time: season.start_date.in_time_zone + 12.hours)
    create(:team_game, game:, team_season: home, team: home.team, home: true)
    create(:team_game, game:, team_season: away, team: away.team, home: false)
    ProphetRatings::GamePredictionBuilder.new(game, ratings_config_version: selected).call
  end

  it 'captures exact reviewed evidence, config, baseline sources and unrounded report then propagates final values once' do
    profile
    report = operation.preview
    row = report[:teams].find { |team| team[:team_id] == home.team_id }
    prior = home.reload.preseason_prior
    formula = ProphetRatings::PreseasonPriorFormula.new(row[:inputs], version.config)
    expect(row).to eq(
      team_id: home.team_id, team_season_id: home.id, added: prior.blank?,
      profile_before: prior&.inputs&.fetch('profile', nil), profile_after: row[:inputs]['profile'],
      outputs_before: prior&.outputs, outputs_after: formula.call,
      coaching: formula.pace_report, efficiency: formula.efficiency_report, inputs: row[:inputs]
    )
    expect(row[:efficiency]).to include(adjustment: 5, offense_allocation: 2.5, defense_allocation: -2.5)
    expect(row[:efficiency][:departures]).to include(reason: 'missing_departure_evidence')
    expect(PreseasonPrior.count).to eq(0)
  end

  it 'captures the approved review identity, raw evidence and baseline provenance' do
    profile
    publish
    prior = home.reload.preseason_prior
    expect(prior.inputs).to include('contract' => 'preseason-v3-reviewed-efficiency', 'configuration' => version.config)
    expect(prior.inputs.dig('reviewed_recruiting', 'revision')).to include('id' => profile.recruiting_revision_id,
                                                                           'input_hash' => profile.recruiting_revision.input_hash)
    expect(prior.inputs.dig('reviewed_recruiting', 'review', 'approval', 'approved_by')).to eq('Test operator')
    expect(prior.inputs.fetch('baseline_sources')).to include('adj_offensive_efficiency' => 'previous_season.average_efficiency')
    expect(prior.inputs.dig('efficiency_adjustment', 'recruiting', 'baseline', 'adj_offensive_efficiency', 'value')).to eq(100)
  end

  it 'propagates the final efficiency once into live ratings, snapshots and frozen predictions' do
    profile
    publish
    prior = home.reload.preseason_prior
    expect(home.attributes.values_at('adj_offensive_efficiency', 'adj_defensive_efficiency', 'adj_pace')).to eq([102.5, 97.5, 68.3])
    snapshot = home.team_rating_snapshots.find_by!(ratings_config_version: version)
    expect(snapshot.stats.dig('preseason_prior', 'inputs')).to eq(prior.inputs)
    expect(snapshot.adj_offensive_efficiency).to eq(102.5)
    prediction = forecast(version)
    expect(prediction.calculation_context.dig('snapshots', 0, 'ratings', 'adj_offensive_efficiency')).to eq(102.5)
  end

  it 'captures approved annual departure accounting and allocates its loss together with recruiting' do
    profile
    review = { 'decision' => 'approved', 'reviewed_by' => 'Test operator', 'reviewed_at' => Time.current.iso8601 }
    dataset = { 'draft_year' => 2026, 'prior_season_year' => 2026, 'target_year' => 2027,
                'expected_picks' => [1], 'failures' => [], 'sources' => [{ 'source_id' => 'synthetic', 'sha256' => 'c' * 64 }] }
    stint = { 'source_id' => 'synthetic', 'player_source_url' => 'https://school.example/player/1', 'team_id' => home.team_id,
              'player_points' => 800, 'team_points' => 2000, 'games' => 10, 'scope' => Departures::Contract::SCOPE,
              'units' => Departures::ProductionStint::UNITS }
    selections = [{ 'selection_key' => '2026/1', 'overall_pick' => 1, 'status' => 'eligible_prior_season', 'stints' => [stint],
                    'candidate_team_ids' => [] }]
    payload = { 'kind' => 'departures', 'dataset_hash' => 'b' * 64, 'review_hash' => Departures::Contract.digest(review),
                'review' => review, 'dataset' => dataset, 'report' => { 'selections' => selections },
                'team_inputs' => { home.team_id.to_s => {} } }
    revision = OffseasonInputRevision.create!(season:, kind: 'departures', version: 'synthetic-loss', reason: 'Test review',
                                              input_hash: Departures::Contract.digest(payload), dataset_hash: payload['dataset_hash'],
                                              review_hash: payload['review_hash'], payload:)
    profile.update!(departure_revision: revision)
    publish
    prior = home.reload.preseason_prior
    expect(prior.inputs.dig('reviewed_departures', 'revision')).to include('id' => revision.id, 'input_hash' => revision.input_hash)
    expect(prior.inputs.dig('reviewed_departures', 'selections')).to eq(selections.as_json)
    expect(prior.inputs.dig('efficiency_adjustment', 'departures')).to include('loss_share' => 0.4, 'contribution' => -0.8)
    expect(prior.outputs).to eq('preseason_adj_offensive_efficiency' => 102.1,
                                'preseason_adj_defensive_efficiency' => 97.9, 'preseason_adj_pace' => 68.3)
    expect(ProphetRatings::PreseasonPriorFormula.new(prior.inputs, version.config).call).to eq(prior.outputs)
  end

  it 'reuses immutable captures after profile/history edits without reading current evidence or model defaults' do
    profile
    initializer = ProphetRatings::PreseasonInitializer.new(season, ratings_config_version: version)
    initializer.call
    prior = home.reload.preseason_prior
    original = prior.attributes
    profile.update!(recruiting_revision: revision('65'))
    previous.team_seasons.first.update!(adj_offensive_efficiency: 150)
    allow(OffseasonInputRevision).to receive(:find).and_raise('mutable evidence read')
    allow(Season).to receive(:find_by).and_raise('mutable history read')
    allow(RatingsConfigVersion).to receive(:authored_config).and_raise('mutable defaults read')
    initializer.call
    expect(home.reload.preseason_prior.attributes).to eq(original)
    expect(ProphetRatings::PreseasonPriorFormula.new(prior.inputs, prior.inputs.fetch('configuration')).call).to eq(prior.outputs)
    expect(initializer.preview[:teams].find { |row| row[:team_id] == home.team_id }[:efficiency][:adjustment]).to eq(5)
  end

  it 'binds evidence pointers to the preview and rejects edits under the same published version' do
    profile
    report = operation.preview
    profile.update!(recruiting_revision: revision('65'))
    expect { operation.call(preview_key: report[:preview_key]) }.to raise_error(ArgumentError, /rerun.*preview/)
    expect(PreseasonPrior.count).to eq(0)
    publish
    profile.update!(recruiting_revision: revision('66'))
    expect { operation.preview }.to raise_error(ArgumentError, /new MODEL_VERSION/)
  end

  it 'tunes via a new config-only revision, preserves old priors/snapshots/forecasts and changes no evidence' do
    profile
    publish
    old_prediction = forecast(version)
    old_rows = [PreseasonPrior.where(ratings_config_version: version).map(&:attributes),
                TeamRatingSnapshot.where(ratings_config_version: version).map(&:attributes), old_prediction.attributes]
    tuned = version.config.deep_dup
    tuned['bundle_name'] = 'reviewed-r3-tuned'
    tuned['preseason']['efficiency_adjustment']['upper_bound'] = 1.0
    selected = RatingsConfigVersion.publish!(tuned)
    changed = described_class.new(season, ratings_config_version: selected)
    report = changed.preview
    expect(report[:teams].first[:efficiency]).to include(pre_cap_sum: 5, adjustment: 1)
    expect { changed.call(preview_key: report[:preview_key]) }.not_to change(OffseasonInputRevision, :count)
    expect(home.reload.attributes.values_at('adj_offensive_efficiency', 'adj_defensive_efficiency')).to eq([100.5, 99.5])
    expect([PreseasonPrior.where(ratings_config_version: version).map(&:attributes),
            TeamRatingSnapshot.where(ratings_config_version: version).map(&:attributes), old_prediction.reload.attributes]).to eq(old_rows)
    expect(ProphetRatings::PreseasonPriorFormula.new(old_rows[0].first['inputs'], version.config).call).to eq(old_rows[0].first['outputs'])
  end

  it 'rolls back captures, ratings and selected revision when publication fails' do
    profile
    original = home.attributes
    snapshots = instance_double(ProphetRatings::TeamRatingSnapshotService)
    allow(ProphetRatings::TeamRatingSnapshotService).to receive(:new).and_return(snapshots)
    allow(snapshots).to receive(:call).and_raise('publication failed')
    expect { publish }.to raise_error('publication failed')
    expect([PreseasonPrior.count, TeamRatingSnapshot.count, season.reload.preseason_revision_id]).to eq([0, 0, nil])
    expect(home.reload.attributes).to eq(original)
  end

  it 'coexists with reviewed coaching pace and preserves coaching eligibility and its separate adjustment' do
    profile
    config[:preseason][:coaching] = { formula: 'relative_pace_v2', weight: 0.5 }
    CoachingReview.create!(year: 2027, ready: true)
    source = create(:team)
    create(:team_season, season: previous, team: source, adj_pace: 76)
    CoachingChange.create!(team: home.team, previous_team: source, effective_year: 2027, previous_year: 2026,
                           coach_name: 'Synthetic Coach', previous_role: 'head_coach', full_season_head_coach: true,
                           previous_season_d1: true, status: 'confirmed')
    CoachingReview.find_by!(year: 2027).update!(ready: true)
    publish
    expect(home.reload.attributes.values_at('adj_offensive_efficiency', 'adj_defensive_efficiency', 'adj_pace')).to eq([102.5, 97.5, 72.15])
    expect(ProphetRatings::PreseasonPriorFormula.new(home.preseason_prior.inputs, version.config).pace_report).to include(signal: 76)
  end

  it 'replays equal CBBD class points into identical combined preseason outputs without live acquisition' do
    profile
    publish
    prior = home.reload.preseason_prior
    captured = prior.inputs.deep_dup
    captured['reviewed_recruiting']['units']['class_points'] = 'cbbd_recruit_composite_class_points'
    allow(Ingestion::Cbbd::HttpTransport).to receive(:call).and_raise('Replay must not fetch')
    expect(ProphetRatings::PreseasonPriorFormula.new(captured, version.config).call).to eq(prior.outputs)
    expect(prior.outputs).to include('preseason_adj_offensive_efficiency' => 102.5, 'preseason_adj_defensive_efficiency' => 97.5)
    expect(Ingestion::Cbbd::HttpTransport).not_to have_received(:call)
  end
end
