# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::PreseasonRatingsCalculator do
  let(:season) { create(:season, year: 2027) }
  let(:teams) { create_list(:team_season, 3, season:) }
  let(:config) do
    RatingsConfigVersion.authored_config.merge(bundle_name: 'shared-evidence').tap do |settings|
      settings[:preseason].merge!(YAML.load_file(Rails.root.join('config/examples/reviewed_efficiency_r3.yml')).deep_symbolize_keys)
    end
  end
  let(:version) { RatingsConfigVersion.publish!(config) }
  let(:review) do
    { 'decision' => 'approved', 'reviewed_by' => 'Synthetic reviewer', 'reviewed_at' => Time.current.iso8601,
      'decisions' => [{ 'reason' => 'retained in annual revision', 'evidence' => 'x' * 10_000 }] }
  end
  let(:source) { { 'id' => 'synthetic', 'snapshot_sha256' => 'a' * 64, 'rows' => [{ 'unused' => 'x' * 10_000 }] } }
  let(:dataset) do
    { 'draft_year' => 2026, 'prior_season_year' => 2026, 'target_year' => 2027,
      'expected_picks' => [1], 'failures' => [], 'sources' => [source] }
  end
  let(:stint) do
    { 'source_id' => 'synthetic', 'player_source_url' => 'https://school.example/player/1', 'team_id' => teams.first.team_id,
      'player_points' => 800, 'team_points' => 2000, 'games' => 10, 'scope' => Departures::Contract::SCOPE,
      'units' => Departures::ProductionStint::UNITS,
      'scope_rows' => { 'regular' => { 'team_points' => 2000, 'players' => source['rows'], 'raw_team_row' => source['rows'] } } }
  end
  let(:selections) do
    [{ 'selection_key' => '2026/1', 'overall_pick' => 1, 'status' => 'eligible_prior_season', 'stints' => [stint] }]
  end
  let(:revision) do
    payload = { 'kind' => 'departures', 'dataset_hash' => 'b' * 64, 'review_hash' => Departures::Contract.digest(review),
                'review' => review, 'dataset' => dataset, 'report' => { 'selections' => selections },
                'team_inputs' => teams.to_h { |team| [team.team_id.to_s, {}] } }
    OffseasonInputRevision.create!(season:, kind: 'departures', version: 'shared', reason: 'Synthetic evidence',
                                   input_hash: Departures::Contract.digest(payload), dataset_hash: payload['dataset_hash'],
                                   review_hash: payload['review_hash'], payload:)
  end

  before do
    teams.each do |team|
      create(:team_offseason_profile, team_season: team, departure_revision: revision,
                                      recruiting_score: nil, returning_minutes_pct: nil, manual_adjustment: nil)
    end
  end

  it 'loads and validates a shared immutable revision once for a complete preview' do
    loads = []
    hashes = []
    subscriber = ActiveSupport::Notifications.subscribe('instantiation.active_record') do |event|
      loads << event.payload[:record_count] if event.payload[:class_name] == 'OffseasonInputRevision'
    end
    allow(Departures::Contract).to receive(:digest).and_wrap_original do |original, value|
      hashes << value if value.is_a?(Hash) && value['kind'] == 'departures'
      original.call(value)
    end
    report = PreseasonPublicationPreview.new(season, ratings_config_version: version, mode: 'initialize').call
    expect(report['teams'].size).to eq(3)
    expect(loads.sum).to eq(1)
    expect(hashes.size).to eq(1)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it 'shares annual revisions within each operation without retaining raw payloads in the request query cache' do
    cached_reads = []
    subscriber = lambda do |event|
      payload = event.payload
      cached_reads << (payload[:cached] == true) if payload[:sql].start_with?('SELECT "offseason_input_revisions".*')
    end
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      ActiveRecord::Base.cache do
        2.times do
          calculator = described_class.new(season, ratings_config_version: version)
          teams.each do |team|
            inputs = calculator.preview_inputs(team)
            expect(inputs.dig(:reviewed_departures, 'revision', 'input_hash')).to eq(revision.input_hash)
          end
        end
      end
    end
    expect(cached_reads).to eq([false, false])
  end

  it 'releases validated raw evidence from bound profiles while preserving stored inputs', :aggregate_failures do
    revisions = ProphetRatings::ReviewedInputRevisions.new
    profiles = teams.first(2).map(&:team_offseason_profile)
    profiles.each { |profile| revisions.bind(profile) }
    full_record = profiles.first.departure_revision
    calculator = described_class.new(season, ratings_config_version: version, reviewed_revisions: revisions)
    inputs = calculator.preview_inputs(teams.first)
    projected = profiles.first.departure_revision
    expect(projected).not_to equal(full_record)
    expect(profiles.last.departure_revision).to equal(projected)
    expect(projected.payload.keys).to contain_exactly('team_inputs', 'review')
    expect(projected.attributes_before_type_cast.fetch('payload').keys).to contain_exactly('team_inputs', 'review')
    expect(projected.changes).to be_empty
    expect(projected).to be_readonly
    expect(inputs.dig(:reviewed_departures, 'revision', 'input_hash')).to eq(revision.input_hash)
    expect(ProphetRatings::DepartureContributionEvidence.new(inputs[:reviewed_departures], teams.first.team_id, season.year).call)
      .to include('loss_share' => 0.4, 'known_points_subtotal' => 800, 'team_points' => 2000)
    expect(OffseasonInputRevision.find(revision.id).payload).to eq(revision.payload)
    expect(calculator.preview_inputs(teams.last).dig(:reviewed_departures, 'revision', 'input_hash')).to eq(revision.input_hash)
    expect(teams.last.team_offseason_profile.departure_revision).to equal(projected)
  end

  it 'checks the complete annual payload hash before releasing any raw evidence' do
    tampered = revision.payload.deep_dup
    tampered.fetch('dataset').fetch('sources').first['rows'] = [{ 'tampered' => true }]
    connection = OffseasonInputRevision.connection
    connection.execute("UPDATE offseason_input_revisions SET payload = #{connection.quote(tampered.to_json)}::jsonb " \
                       "WHERE id = #{revision.id}")
    calculator = described_class.new(season, ratings_config_version: version)
    expect { calculator.preview_inputs(teams.first) }.to raise_error(ArgumentError, /Input hash does not match retained evidence/)
  end

  it 'captures all accounting and source identities without raw source or roster copies' do
    inputs = described_class.new(season, ratings_config_version: version).preview_inputs(teams.first).deep_stringify_keys
    captured = inputs.fetch('reviewed_departures')
    legacy = dataset.merge('selections' => selections, 'review' => review)
    expect(captured['sources']).to eq([source.except('rows')])
    expect(captured.dig('selections', 0, 'stints', 0, 'scope_rows', 'regular')).to eq('team_points' => 2000)
    expect(captured).to include('revision' => include('id' => revision.id, 'input_hash' => revision.input_hash),
                                'review' => review.except('decisions'))
    expect(ProphetRatings::DepartureContributionEvidence.new(captured, teams.first.team_id, season.year).call)
      .to eq(ProphetRatings::DepartureContributionEvidence.new(legacy, teams.first.team_id, season.year).call)
      .and include('loss_share' => 0.4, 'known_points_subtotal' => 800, 'team_points' => 2000)
    inputs['previous_values'] = { 'adj_offensive_efficiency' => 100, 'adj_defensive_efficiency' => 100, 'adj_pace' => 68 }
    inputs['baselines'] = { 'adj_offensive_efficiency' => 100, 'adj_defensive_efficiency' => 100, 'adj_pace' => 70 }
    expect(ProphetRatings::PreseasonPriorFormula.new(inputs, version.config).call)
      .to eq(ProphetRatings::PreseasonPriorFormula.new(inputs.merge('reviewed_departures' => legacy), version.config).call)
      .and eq('preseason_adj_offensive_efficiency' => 99.6, 'preseason_adj_defensive_efficiency' => 100.4,
              'preseason_adj_pace' => 68.3)
  end

  it 'recognizes historical full-body revision captures without rewriting them or ignoring changed operands' do
    inputs = described_class.new(season, ratings_config_version: version).preview_inputs(teams.first).as_json
    historical = inputs.deep_dup
    historical['reviewed_departures']['sources'] = [source]
    historical['reviewed_departures']['selections'] = selections
    historical['reviewed_departures']['review'] = review
    outputs = ProphetRatings::PreseasonPriorFormula.new(inputs, version.config).call
    prior = PreseasonPrior.create!(team_season: teams.first, ratings_config_version: version, inputs: historical, outputs:)
    row = { team_season_id: teams.first.id, inputs:, outputs_after: outputs }
    captures = PreseasonPrior.where(ratings_config_version: version)
    expect(ProphetRatings::PreseasonRevision.matching_capture?(captures, row)).to be(true)
    expect(prior.reload.inputs).to eq(historical)
    inputs['reviewed_departures']['selections'][0]['stints'][0]['player_points'] = 700
    expect(ProphetRatings::PreseasonRevision.matching_capture?(captures, row)).to be(false)
  end

  it 'bounds reports reusing historical raw captures while preserving stored replay and before values' do
    inputs = described_class.new(season, ratings_config_version: version).preview_inputs(teams.first).as_json
    inputs['reviewed_departures'].merge!('sources' => [source], 'selections' => selections, 'review' => review)
    outputs = ProphetRatings::PreseasonPriorFormula.new(inputs, version.config).call
    prior = PreseasonPrior.create!(team_season: teams.first, ratings_config_version: version, inputs:, outputs:)
    teams.first.update!(preseason_prior: prior)
    report = ProphetRatings::PreseasonInitializer.new(season, ratings_config_version: version).preview
    entry = report[:teams].find { |row| row[:team_id] == teams.first.team_id }
    expect(entry.dig(:inputs, 'reviewed_departures', 'sources')).to eq([source.except('rows')])
    expect(entry[:outputs_before]).to eq(outputs)
    expect(entry[:outputs_after]).to eq(outputs)
    expect(prior.reload.inputs).to eq(inputs)
  end

  it 'loads only identity and outputs when applying an existing prior' do
    inputs = described_class.new(season, ratings_config_version: version).preview_inputs(teams.first).as_json
    outputs = ProphetRatings::PreseasonPriorFormula.new(inputs, version.config).call
    prior = PreseasonPrior.create!(team_season: teams.first, ratings_config_version: version, inputs:, outputs:)
    calculator = described_class.new(season, ratings_config_version: version)
    loaded = calculator.send(:captured_prior, teams.first, version)
    expect(loaded.attribute_names).not_to include('inputs')
    expect(loaded.attributes).to include('id' => prior.id, 'team_season_id' => teams.first.id,
                                         'ratings_config_version_id' => version.id, 'outputs' => outputs)
    expect(prior.reload.inputs).to eq(inputs)
  end

  it 'loads shared annual evidence once across publication validation, writing and final identity' do
    admin = create(:user, :admin)
    PreseasonPublication.select_model(season, version)
    publication = PreseasonPublication.review!(season, reviewer: admin, mode: 'initialize')
    PreviewPreseasonJob.perform_now(publication.id)
    publication.reload
    allow(PublishPreseasonJob).to receive(:perform_later).and_return(true)
    PreseasonPublicationQueue.new(publication, actor: admin, fingerprint: publication.fingerprint, acknowledge: '1').call
    loads = []
    subscriber = ActiveSupport::Notifications.subscribe('instantiation.active_record') do |event|
      loads << event.payload[:record_count] if event.payload[:class_name] == 'OffseasonInputRevision'
    end
    PreseasonPublicationExecution.new(publication).call
    expect(publication.reload.status).to eq('published')
    expect(PreseasonPrior.count).to eq(3)
    expect(loads.sum).to eq(1)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
