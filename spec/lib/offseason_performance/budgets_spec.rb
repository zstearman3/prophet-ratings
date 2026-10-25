# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/performance/budgets')
require Rails.root.join('script/performance/content')

RSpec.describe OffseasonPerformance::Budgets do
  def samples
    Array.new(30) { { 'elapsed' => 1.0, 'valid' => true, 'telemetry' => {}, 'current_bytes' => 100_000_000 } }
  end

  it 'uses nearest-rank p95, including the 29th of 30 samples' do
    expect(described_class.percentile((1..30).to_a)).to eq(29)
    expect(described_class.percentile([])).to be_nil
  end

  it 'passes exact limits and fails immediately above latency and absolute median drift limits' do
    values = samples
    expect(described_class.window(values, limit: 1)).to be_empty
    values.last(10).each { |value| value['current_bytes'] += 20 * described_class::MIB }
    expect(described_class.window(values, limit: 1)).to be_empty
    values.last(10).each { |value| value['current_bytes'] += 1 }
    values.last(2).each { |value| value['elapsed'] = 1.01 }
    expect(described_class.window(values, limit: 1).size).to eq(2)
  end

  it 'fails closed for incomplete or invalid samples' do
    expect(described_class.window(samples.first(29), limit: 1)).not_to be_empty
    values = samples
    values[0]['telemetry'] = nil
    expect(described_class.window(values, limit: 1)).not_to be_empty
    values[0]['valid'] = false
    expect(described_class.window(values, limit: 1)).not_to be_empty
  end

  it 'rejects OOM and missing counters and accepts exactly 400 MiB' do
    expect(described_class.container([], { 'OOMKilled' => true })).to include('OOMKilled', 'missing container measurements')
    expect(described_class.container([{ 'peak_bytes' => 400 * described_class::MIB, 'current_bytes' => 100 }], {})).to be_empty
    expect(described_class.container([{ 'peak_bytes' => (400 * described_class::MIB) + 1, 'current_bytes' => 100 }], {})).not_to be_empty
  end

  it 'rejects an exited container even when earlier samples were within budget' do
    values = [{ 'peak_bytes' => 100, 'current_bytes' => 100 }]
    expect(described_class.container(values, { 'Running' => false })).to include('container exited unexpectedly')
  end
end
