# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::PreseasonReportBuilder do
  let(:row) { Struct.new(:id, :team_id).new(42, 7) }
  let(:config) { RatingsConfigVersion.authored_config }
  let(:expected_keys) do
    %i[
      team_id team_season_id added profile_before profile_after outputs_before
      outputs_after coaching efficiency inputs
    ]
  end
  let(:inputs) do
    {
      'contract' => 'preseason-v1',
      'baselines' => { 'adj_offensive_efficiency' => 110.0, 'adj_defensive_efficiency' => 100.0, 'adj_pace' => 70.0 },
      'previous_values' => { 'adj_offensive_efficiency' => 100.0, 'adj_defensive_efficiency' => 110.0, 'adj_pace' => 68.0 },
      'profile_values' => { 'recruiting_score' => 20.0, 'returning_minutes_pct' => 0.8, 'manual_adjustment' => 1.0 },
      'profile' => { 'attributes' => { 'source_reference' => 'Synthetic source' } }
    }
  end
  let(:prior) do
    Struct.new(:inputs, :outputs).new(
      { 'profile' => { 'attributes' => { 'source_reference' => 'Earlier source' } } },
      { 'preseason_adj_offensive_efficiency' => 101.0, 'preseason_adj_defensive_efficiency' => 109.0,
        'preseason_adj_pace' => 68.3 }
    )
  end

  it 'returns the ordered legacy row contract and rounded v1 outputs' do
    report = described_class.new(row, inputs, config, prior:).call

    expect(report.keys).to eq(expected_keys)
    expect(report.slice(:team_id, :team_season_id, :added, :profile_before, :profile_after, :outputs_before,
                        :outputs_after, :coaching, :efficiency, :inputs)).to eq(
                          team_id: 7, team_season_id: 42, added: false, profile_before: prior.inputs['profile'],
                          profile_after: inputs['profile'], outputs_before: prior.outputs,
                          outputs_after: { 'preseason_adj_offensive_efficiency' => 103.5,
                                           'preseason_adj_defensive_efficiency' => 106.5, 'preseason_adj_pace' => 68.3 },
                          coaching: nil, efficiency: nil, inputs: inputs
                        )
    expect(report[:outputs_after].values).to all(be_a(Float))
  end

  it 'keeps the v2 coaching detail in the shared row with its unrounded report values' do
    coaching_config = config.deep_dup
    coaching_config[:preseason][:coaching] = { formula: 'relative_pace_v2', weight: 0.5 }
    coaching_inputs = inputs.merge('contract' => 'preseason-v2-coaching',
                                   'coaching' => { 'reason' => 'no_confirmed_move', 'target_anchor' => 70.0 })

    report = described_class.new(row, coaching_inputs, coaching_config, prior:).call

    expect(report.keys).to eq(expected_keys)
    expect(report.slice(:outputs_after, :efficiency)).to eq(
      outputs_after: { 'preseason_adj_offensive_efficiency' => 103.5,
                       'preseason_adj_defensive_efficiency' => 106.5, 'preseason_adj_pace' => 68.3 },
      efficiency: nil
    )
    expect(report[:coaching]).to include(reason: 'no_confirmed_move', old_pace: 68.3, signal: nil,
                                         weight: 0.5, adjustment: 0, new_pace: 68.3)
    expect(report[:coaching].values_at(:old_pace, :weight, :new_pace)).to all(be_a(Float))
  end

  it 'preserves partial previous-season history and falls back per missing statistic' do
    partial_inputs = inputs.deep_dup
    partial_inputs['previous_values']['adj_defensive_efficiency'] = nil

    report = described_class.new(row, partial_inputs, config, prior:).call

    expect(report[:outputs_after]).to eq(
      'preseason_adj_offensive_efficiency' => 103.5,
      'preseason_adj_defensive_efficiency' => 98.0,
      'preseason_adj_pace' => 68.3
    )
    expect(report[:inputs]['previous_values']['adj_defensive_efficiency']).to be_nil
  end

  it 'reports an added team with missing prior and profile values' do
    no_profile = inputs.except('profile')

    report = described_class.new(row, no_profile, config, prior: nil).call

    expect(report.values_at(:added, :profile_before, :profile_after, :outputs_before)).to eq([true, nil, nil, nil])
  end

  it 'uses the explicitly supplied prior for provenance and constructs one formula for the row' do
    allow(ProphetRatings::PreseasonPriorFormula).to receive(:new).and_call_original
    report = described_class.new(row, inputs, config, prior:).call

    expect(ProphetRatings::PreseasonPriorFormula).to have_received(:new).once
    expect(report[:outputs_before]).to eq(prior.outputs)
  end

  it 'runs without SQL when row, prior, inputs and configuration are supplied' do
    supplied_config = config
    supplied_inputs = inputs
    notifications = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      notifications << payload unless payload[:name]&.match?(/SCHEMA|TRANSACTION/)
    end

    described_class.new(row, supplied_inputs, supplied_config, prior:).call

    expect(notifications).to be_empty
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  it 'hashes each team independently while binding every operand and preserving JSON key ordering' do
    report = { 'season_id' => 7, 'teams' => [{ 'team_id' => 1, 'inputs' => { 'pace' => 68.3, 'offense' => 100 } }] }
    allow(report).to receive(:as_json).and_raise('Do not copy the entire report tree')
    original = described_class.fingerprint(report)
    reordered = { 'teams' => [{ 'inputs' => { 'offense' => 100, 'pace' => 68.3 }, 'team_id' => 1 }], 'season_id' => 7 }
    expect(described_class.fingerprint(reordered)).to eq(original)
    reordered['teams'][0]['inputs']['pace'] = 69
    expect(described_class.fingerprint(reordered)).not_to eq(original)
    expect(original).to match(/\A[a-f0-9]{64}\z/)
  end
end
