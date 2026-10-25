# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/performance/runner')
require Rails.root.join('script/performance/driver')

RSpec.describe OffseasonPerformance::Measurements do
  def sample
    { 'valid' => true, 'telemetry' => { 'status' => 200 }, 'current_bytes' => 100,
      'elapsed' => 0.1, 'worker_current' => { 'current_bytes' => 100 } }
  end

  def phase_result(name, phase, cold)
    result = { 'scenario' => name, 'phase' => phase, 'failures' => [],
               'warmups' => Array.new(10) { sample }, 'samples' => Array.new(30) { sample } }
    result['cold'] = cold unless cold == :missing
    described_class.check(result, limit: 1)
    result
  end

  def result_for(name, cold = :missing)
    phases = OffseasonPerformance::Scenario::GETS.include?(name) ? %w[serial concurrent] : ['serial']
    result = { 'errors' => [], 'container_windows' => [], 'scenarios' => phases.map { |phase| phase_result(name, phase, cold) } }
    result['coverage'] = OffseasonPerformance::RunVerdict.coverage(result, [name])
    result['pass'] = OffseasonPerformance::RunVerdict.passed?(result)
    result
  end

  it 'treats complete cold latency above 3s as only a budget breach in both modes' do
    result = result_for('preseason', sample.merge('elapsed' => 3.001))
    expect(result['pass']).to be(false)
    expect(OffseasonPerformance::RunVerdict.exit_code(result, assert: false)).to eq(0)
    expect(OffseasonPerformance::RunVerdict.exit_code(result, assert: true)).to eq(1)
  end

  it 'accepts exactly 3s and finite nonnegative zero measurements' do
    expect(result_for('preseason', sample.merge('elapsed' => 3.0))['pass']).to be(true)
    expect(result_for('preseason', sample.merge('elapsed' => 0, 'current_bytes' => 0))['pass']).to be(true)
  end

  it 'fails closed for absent, invalid or incomplete cold GET evidence in either mode' do
    cases = [:missing, nil, {}, sample.merge('valid' => false), sample.merge('telemetry' => nil),
             sample.merge('telemetry' => {}), sample.merge('current_bytes' => nil), sample.merge('elapsed' => nil)]
    cases.each do |cold|
      result = result_for('preseason', cold)
      expect(result['pass']).to be(false)
      expect(OffseasonPerformance::RunVerdict.exit_code(result, assert: false)).to eq(2)
      expect(OffseasonPerformance::RunVerdict.exit_code(result, assert: true)).to eq(2)
    end
  end

  it 'rejects nonfinite, negative or nonnumeric cold elapsed and memory values' do
    %w[elapsed current_bytes].product([Float::NAN, Float::INFINITY, -0.1, '0.1']).each do |field, value|
      result = result_for('preseason', sample.merge(field => value))
      expect(result['pass']).to be(false)
      expect(OffseasonPerformance::RunVerdict.exit_code(result, assert: false)).to eq(2)
      expect(OffseasonPerformance::RunVerdict.exit_code(result, assert: true)).to eq(2)
    end
  end

  it 'does not require cold samples for status, queue or synchronous comparison routes' do
    %w[status preview publish schedule compare].each do |name|
      result = result_for(name)
      expect(result['pass']).to be(true)
      expect(OffseasonPerformance::RunVerdict.exit_code(result, assert: true)).to eq(0)
    end
  end

  describe 'worker memory file reads' do
    let(:path) { '/benchmark/worker-current.json' }

    before { allow(described_class).to receive(:sleep) }

    it 'recovers a transient missing file without retrying a request or inventing telemetry' do
      reads = 0
      allow(File).to receive(:read).with(path) do
        reads += 1
        raise Errno::ENOENT, path if reads < 3

        '{"current_bytes":123}'
      end
      metrics = described_class.response_metrics({ 'status' => 200, 'body' => 'ok' }, { 'current_bytes' => 42 })
      expect(metrics).to include('worker_current' => { 'current_bytes' => 123, 'sampler_read_retries' => 2 }, 'status' => 200,
                                 'current_bytes' => 42, 'output_bytes' => 2)
      expect(reads).to eq(3)
    end

    it 'records zero retry delay when the first read succeeds' do
      allow(File).to receive(:read).with(path).and_return('{"current_bytes":123}')
      metrics = described_class.response_metrics({ 'status' => 200, 'body' => '' }, nil)
      expect(metrics.fetch('worker_current')).to eq('current_bytes' => 123, 'sampler_read_retries' => 0)
      expect(File).to have_received(:read).with(path).once
      expect(described_class).not_to have_received(:sleep)
    end

    it 'raises after five missing-file attempts and at most 200ms of configured delay' do
      allow(File).to receive(:read).with(path).and_raise(Errno::ENOENT, path)
      expect { described_class.response_metrics({ 'status' => 200, 'body' => '' }, nil) }.to raise_error(Errno::ENOENT)
      expect(File).to have_received(:read).with(path).exactly(5).times
      expect(described_class).to have_received(:sleep).with(0.05).exactly(4).times
    end

    it 'fails immediately on malformed JSON rather than reusing or defaulting memory' do
      allow(File).to receive(:read).with(path).and_return('{')
      expect { described_class.response_metrics({ 'status' => 200, 'body' => '' }, nil) }.to raise_error(JSON::ParserError)
      expect(File).to have_received(:read).with(path).once
      expect(described_class).not_to have_received(:sleep)
    end

    it 'does not retry non-ENOENT filesystem failures' do
      allow(File).to receive(:read).with(path).and_raise(Errno::EACCES, path)
      expect { described_class.response_metrics({ 'status' => 200, 'body' => '' }, nil) }.to raise_error(Errno::EACCES)
      expect(File).to have_received(:read).with(path).once
      expect(described_class).not_to have_received(:sleep)
    end
  end
end
