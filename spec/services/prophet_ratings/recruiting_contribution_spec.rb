# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::RecruitingContribution do
  let(:config) do
    RatingsConfigVersion.authored_config.deep_dup.tap do |payload|
      payload[:preseason][:recruiting] = YAML.load_file(Rails.root.join('config/examples/recruiting_r3.yml')).symbolize_keys
    end
  end
  let(:inputs) do
    { contract: config.dig(:preseason, :coaching) ? 'preseason-v2-coaching' : 'preseason-v1',
      previous_values: { adj_offensive_efficiency: 100.0, adj_defensive_efficiency: 100.0 },
      baselines: { adj_offensive_efficiency: 100.0, adj_defensive_efficiency: 100.0 },
      profile_values: {}, reviewed_recruiting: evidence(70) }
  end

  def evidence(points)
    { class_points: points, status: if points.nil?
                                      'unknown'
                                    else
                                      (points.zero? ? 'verified_zero' : 'verified_points')
                                    end,
      units: { class_points: '247_recruit_composite_class_points' }, reason: 'reviewed_source_row' }
  end

  def score(points: 70, net: 0)
    captured = inputs.deep_dup
    captured[:reviewed_recruiting] = evidence(points)
    captured[:previous_values][:adj_offensive_efficiency] += net
    captured[:baselines][:adj_offensive_efficiency] += net
    described_class.new(captured, config).call
  end

  [[0, 5], [10, 11.0 / 3], [20, 7.0 / 3], [30, 1]].each do |net, expected|
    it "returns #{expected} net points per 100 possessions at class 70 and baseline #{net}" do
      report = score(net:)
      expect(report[:contribution]).to be_within(1e-12).of(expected)
      expect(report[:baseline_net]).to eq(net)
      expect(report[:units]).to eq('net_points_per_100_possessions')
    end

    it "halves the benefit at class 65 and baseline #{net}" do
      expect(score(points: 65, net:)[:contribution]).to be_within(1e-12).of(expected / 2.0)
    end
  end

  [[0, 0], [59.999, 0], [60, 0], [60.001, 0.0005], [69.999, 4.9995], [70, 5], [70.001, 5], [1e300, 5]].each do |points, expected|
    it "clamps the class band at #{points} without treating zero as unknown" do
      result = score(points:)
      expect(result[:contribution]).to be_within(1e-12).of(expected)
      expect(result[:reason]).to eq(points <= 60 ? 'below_threshold' : 'eligible')
    end
  end

  [[-1e300, 5], [-0.001, 5], [0, 5], [0.001, 4.999866666666667],
   [29.999, 1.0001333333333333], [30, 1], [30.001, 1], [1e300, 1]].each do |net, expected|
    it "clamps baseline attenuation at #{net}" do
      expect(score(net:)[:contribution]).to be_within(1e-10).of(expected)
    end
  end

  it 'reports unknown separately from verified below-threshold points' do
    expect(score(points: nil)).to include(reason: 'missing_class_points', contribution: 0.0, class_points: nil, eligible: false)
    inputs[:reviewed_recruiting] = nil
    expect(described_class.new(inputs, config).call[:reason]).to eq('missing_class_points')
  end

  it 'uses exact zero weight while retaining the unweighted arithmetic and input eligibility' do
    config[:preseason][:recruiting][:weight] = 0
    expect(score).to include(reason: 'disabled', eligible: true, raw_contribution: 5.0, contribution: 0.0)
    expect(score(points: nil)[:reason]).to eq('missing_class_points')
    expect(score(points: 0)[:reason]).to eq('below_threshold')
  end

  it 'applies the configured weight once and does not round component output' do
    config[:preseason][:recruiting][:weight] = 0.5
    expect(score(net: 10)[:contribution]).to be_within(1e-12).of(11.0 / 6)
  end

  it 'blends history with the captured per-stat baseline before computing net strength' do
    inputs[:previous_values].merge!(adj_offensive_efficiency: 120, adj_defensive_efficiency: 100)
    result = described_class.new(inputs, config).call
    expect(result[:baseline_net]).to eq(17)
    expect(result[:contribution]).to be_within(1e-12).of(41.0 / 15)
    expect(result[:baseline]['adj_offensive_efficiency']).to include(value: 117, fallback: false)
  end

  it 'flags fallback independently and does not let legacy profiles change attenuation' do
    inputs[:previous_values].merge!(adj_offensive_efficiency: nil, adj_defensive_efficiency: 110)
    inputs[:profile_values] = { recruiting_score: 999, returning_minutes_pct: 0, manual_adjustment: -100 }
    result = described_class.new(inputs, config).call
    expect(result[:baseline_net]).to eq(-8.5)
    expect(result[:baseline]['adj_offensive_efficiency']).to include(value: 100, fallback: true)
    expect(result[:baseline]['adj_defensive_efficiency']).to include(value: 108.5, fallback: false)
    expect(result[:contribution]).to eq(5)
  end

  it 'retains exact provider decimal representation and evidence in its replay inputs' do
    inputs[:reviewed_recruiting] = evidence(70).merge(class_points: '65.123456789123456789', row: { source: 'saved-evidence' })
    result = described_class.new(inputs, config).call
    expect(result[:inputs].dig('reviewed_recruiting', 'class_points')).to eq('65.123456789123456789')
    expect(result[:inputs].dig('reviewed_recruiting', 'row')).to eq('source' => 'saved-evidence')
    expect(result[:formula]).to eq('class_points_baseline_v1')
    expect(result[:bundle_name]).to eq(config[:bundle_name])
  end

  { class_points_upper: [80, 7.0 / 6], baseline_net_upper: [60, 11.0 / 3],
    attenuation_floor: [0.4, 3], max_net_efficiency: [3, 1.4] }.each do |key, (value, expected)|
    it "tunes #{key} through config only while preserving an old report's replay" do
      old = score(net: 20)
      config[:bundle_name] = "tuned-#{key}"
      config[:preseason][:recruiting][key] = value
      expect(score(net: 20)[:contribution]).to be_within(1e-12).of(expected)
      expect(described_class.new(old[:inputs], old[:configuration]).call).to eq(old)
      expect(old[:configuration]).to be_frozen
    end
  end

  it 'preserves baseline ordering for equal classes and equal departure losses at initial settings' do
    nets = [0, 10, 20, 30]
    benefit = nets.map { |net| score(net:)[:contribution] }
    expect(benefit).to eq(benefit.sort.reverse)
    final_net = nets.zip(benefit).map { |net, recruiting| net + recruiting - 0.8 }
    expect(final_net).to eq(final_net.sort)
  end

  [-1, Float::NAN, Float::INFINITY, 'invalid', true].each do |points|
    it "rejects invalid class points #{points.inspect} even with weight zero" do
      inputs[:reviewed_recruiting][:class_points] = points
      config[:preseason][:recruiting][:weight] = 0
      expect { described_class.new(inputs, config).call }.to raise_error(ArgumentError, /points/)
    end
  end

  it 'rejects pending evidence, conflicting statuses and non-provider units' do
    inputs[:reviewed_recruiting][:status] = 'pending'
    expect { described_class.new(inputs, config).call }.to raise_error(ArgumentError, /status/)
    inputs[:reviewed_recruiting][:status] = 'unknown'
    expect { described_class.new(inputs, config).call }.to raise_error(ArgumentError, /status/)
    inputs[:reviewed_recruiting][:units][:class_points] = 'ordinal_rank'
    expect { described_class.new(inputs, config).call }.to raise_error(ArgumentError, /units/)
  end

  it 'rejects nonfinite history and missing or invalid baselines instead of fabricating zero' do
    inputs[:previous_values][:adj_offensive_efficiency] = Float::NAN
    expect { described_class.new(inputs, config).call }.to raise_error(ArgumentError, /finite/)
    inputs[:previous_values][:adj_offensive_efficiency] = nil
    inputs[:baselines][:adj_offensive_efficiency] = nil
    expect { described_class.new(inputs, config).call }.to raise_error(ArgumentError, /finite/)
  end

  it 'requires stored numeric efficiencies instead of inconsistently coercing numeric-looking strings' do
    inputs[:previous_values][:adj_offensive_efficiency] = '0x1p6'
    expect { described_class.new(inputs, config).call }.to raise_error(ArgumentError, /numeric/)
    inputs[:previous_values][:adj_offensive_efficiency] = nil
    inputs[:baselines][:adj_offensive_efficiency] = '100'
    expect { described_class.new(inputs, config).call }.to raise_error(ArgumentError, /numeric/)
  end
end
