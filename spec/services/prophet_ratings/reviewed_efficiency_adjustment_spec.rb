# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::ReviewedEfficiencyAdjustment do
  let(:config) do
    RatingsConfigVersion.authored_config.deep_dup.tap do |payload|
      payload[:preseason].merge!(YAML.load_file(Rails.root.join('config/examples/reviewed_efficiency_r3.yml')).deep_symbolize_keys)
    end
  end
  let(:inputs) do
    { contract: 'preseason-v3-reviewed-efficiency', team_id: 1, target_year: 2027,
      previous_values: { adj_offensive_efficiency: 100.0, adj_defensive_efficiency: 100.0, adj_pace: 68.0 },
      baselines: { adj_offensive_efficiency: 100.0, adj_defensive_efficiency: 100.0, adj_pace: 70.0 },
      profile_values: {}, reviewed_recruiting: recruiting(70), reviewed_departures: evidence }
  end
  let(:evidence) do
    { draft_year: 2026, prior_season_year: 2026, target_year: 2027, expected_picks: [1], failures: [],
      review: { decision: 'approved', reviewed_by: 'Synthetic reviewer', reviewed_at: '2026-10-14T12:00:00Z' },
      selections: [{ selection_key: '2026/1', overall_pick: 1, status: 'eligible_prior_season', stints: [stint], candidate_team_ids: [] }] }
  end
  let(:stint) do
    { source_id: 'school', player_source_url: 'https://school.example/player/1', team_id: 1,
      player_points: 800, team_points: 2000, games: 10, scope: Departures::Contract::SCOPE,
      units: Departures::ProductionStint::UNITS }
  end

  def recruiting(points)
    { class_points: points, status: points.zero? ? 'verified_zero' : 'verified_points',
      units: { class_points: '247_recruit_composite_class_points' } }
  end

  def report
    described_class.new(inputs, config).call
  end

  def outputs
    ProphetRatings::PreseasonPriorFormula.new(inputs, config).call
  end

  [[0, 4.2, 102.1, 97.9], [30, 0.2, 130.1, 99.9]].each do |net, adjustment, offense, defense|
    it "attenuates before loss at net #{net} and allocates once without blend reweighting" do
      inputs[:previous_values][:adj_offensive_efficiency] += net
      inputs[:baselines][:adj_offensive_efficiency] += net
      expect(report[:adjustment]).to be_within(1e-12).of(adjustment)
      expect(outputs.values).to eq([offense, defense, 68.3])
      expect(report[:departures]).to include(loss_share: 0.4, raw_contribution: -0.8, contribution: -0.8)
    end
  end

  it 'allocates net +0.8 as +0.4 offense and -0.4 defense' do
    inputs[:reviewed_recruiting] = recruiting(63.2)
    expect(outputs.values).to eq([100.4, 99.6, 68.3])
  end

  it 'applies the combined positive and negative cap exactly once' do
    config[:preseason][:efficiency_adjustment].merge!(lower_bound: -0.5, upper_bound: 0.8)
    expect(report).to include(pre_cap_sum: 4.2, adjustment: 0.8)
    inputs[:reviewed_recruiting] = recruiting(60)
    expect(report).to include(pre_cap_sum: -0.8, adjustment: -0.5)
    expect(outputs.values).to eq([99.75, 100.25, 68.3])
  end

  it 'retains unknown, verified zero, threshold and incomplete-core reasons and per-stat fallback' do
    inputs[:reviewed_recruiting] = nil
    inputs[:reviewed_departures] = nil
    expect(outputs.values).to eq([100, 100, 68.3])
    expect(report[:recruiting]).to include(class_points: nil, reason: 'missing_class_points')
    expect(report[:departures]).to include(loss_share: nil, reason: 'missing_departure_evidence')
  end

  it 'distinguishes verified zero from missing and incomplete-core evidence' do
    inputs[:reviewed_recruiting] = recruiting(0)
    inputs[:reviewed_departures] = evidence
    stint[:player_points] = 0
    expect(report[:recruiting][:reason]).to eq('below_threshold')
    expect(report[:departures]).to include(loss_share: 0, reason: 'verified_zero')
    stint[:player_points] = 800
    inputs[:previous_values][:adj_defensive_efficiency] = nil
    inputs[:reviewed_recruiting] = recruiting(70)
    expect(report[:departures]).to include(loss_share: 0.4, reason: 'no_complete_previous_core', contribution: 0)
    expect(report[:recruiting][:baseline]['adj_defensive_efficiency']).to include(fallback: true, value: 100)
    expect(outputs.values).to eq([102.5, 97.5, 68.3])
  end

  it 'disables each factor independently using only its immutable weight' do
    config[:preseason][:recruiting][:weight] = 0
    expect(report[:adjustment]).to eq(-0.8)
    config[:preseason][:recruiting][:weight] = 1
    config[:preseason][:departures][:weight] = 0
    expect(report[:adjustment]).to eq(5)
    expect(outputs.values).to eq([102.5, 97.5, 68.3])
  end

  it 'dispatches exact legacy profile arithmetic when both weights are zero' do
    inputs[:profile_values] = { recruiting_score: 20, returning_minutes_pct: 0.8, manual_adjustment: 0.25 }
    config[:preseason][:recruiting][:weight] = config[:preseason][:departures][:weight] = 0
    legacy = config.deep_dup
    legacy[:preseason].delete(:efficiency_adjustment)
    old_inputs = inputs.merge(contract: 'preseason-v1')
    expect(outputs).to eq(ProphetRatings::PreseasonPriorFormula.new(old_inputs, legacy).call)
    expect(outputs.values).to eq([101.25, 98.75, 68.3])
    expect(report[:enabled]).to be(false)
  end

  [{ recruiting_score: 10, manual_adjustment: -1 }, { returning_minutes_pct: 0.8, manual_adjustment: 1 }].each do |profile|
    it "rejects individually overlapping legacy components even when #{profile} cancels" do
      inputs[:profile_values] = profile
      expect { outputs }.to raise_error(ArgumentError, /overlap/)
    end
  end

  it 'preserves full precision through allocation and final rounding' do
    inputs[:previous_values][:adj_offensive_efficiency] = 111.1111
    inputs[:reviewed_recruiting] = recruiting(65)
    expect(report[:recruiting][:baseline_net]).to be_within(1e-12).of(9.444435)
    expect(outputs.values).to eq([109.98, 99.465, 68.3])
  end

  it 'refuses to replay frozen inputs with different model coefficients' do
    inputs[:configuration] = config.deep_dup
    config[:preseason][:recruiting][:weight] = 0.5
    expect { outputs }.to raise_error(ArgumentError, /captured immutable configuration/)
  end

  it 'rejects invalid new-contract pace without changing historical contract dispatch' do
    inputs[:baselines][:adj_pace] = nil
    expect { outputs }.to raise_error(ArgumentError, /positive/)
  end

  it 'rejects mismatched contracts without changing v1 component-preview dispatch' do
    inputs[:contract] = 'preseason-v1'
    expect { outputs }.to raise_error(ArgumentError, /contract/)
    config[:preseason].delete(:efficiency_adjustment)
    expect(outputs.values).to eq([100, 100, 68.3])
  end

  [{ formula: 'unknown' }, { lower_bound: 1 }, { upper_bound: -1 }, { lower_bound: Float::NAN },
   { upper_bound: Float::INFINITY }, { upper_bound: nil }].each do |change|
    it "rejects invalid combined configuration #{change}" do
      config[:preseason][:efficiency_adjustment].merge!(change)
      expect { report }.to raise_error(ArgumentError, /formula|bounds/)
    end
  end
end
