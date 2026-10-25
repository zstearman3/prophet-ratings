# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/performance/telemetry')
require Rails.root.join('script/performance/driver')
require Rails.root.join('script/performance/solver_job')
require Rails.root.join('script/performance/mixed_jobs')

RSpec.describe OffseasonPerformance::MixedWorkload do
  def delivery(start, finish)
    { 'created_at' => start - 1, 'started_at' => start, 'finished_at' => finish, 'process_id' => 'one-worker',
      'active_job_id' => SecureRandom.uuid, 'arguments' => ['token', 1, 2], 'error' => nil }
  end

  let(:evidence) { [delivery(1, 20), delivery(20, 30), delivery(11, 12).merge('created_at' => 1)] }
  let(:samples) { Array.new(30) { { 'started_at' => 2, 'finished_at' => 19 } } }

  it 'enqueues two distinct heavy deliveries before readiness and ordinary work with identical pins' do
    scenario = instance_double(OffseasonPerformance::Scenario, fixture: { 'season_id' => 1, 'model_id' => 2 })
    allow(SecureRandom).to receive(:hex).with(12).and_return('token')
    workload = described_class.new(scenario)
    first, second, ordinary = Array.new(3) { |index| double(job_id: index.to_s) }
    events = []
    deliveries = [first, second]
    allow(OffseasonPerformance::MixedHeavyJob).to receive(:perform_later) { |*args|
      events << ['heavy', args]
      deliveries.shift
    }
    allow(workload).to receive(:await_ready) { |job| events << ['ready', job.job_id] }
    allow(OffseasonPerformance::MixedOrdinaryJob).to receive(:perform_later) { |*args|
      events << ['ordinary', args]
      ordinary
    }
    expect(workload.enqueue).to eq([first, second, ordinary])
    expect(events).to eq([['heavy', ['token', 1, 2]], ['heavy', ['token', 1, 2]], %w[ready 0], ['ordinary', ['token', 1, 2]]])
  end

  it 'rejects readiness for a different heavy delivery before enqueuing ordinary work' do
    scenario = instance_double(OffseasonPerformance::Scenario, fixture: { 'season_id' => 1, 'model_id' => 2 })
    workload = described_class.new(scenario)
    allow(OffseasonPerformance::MixedHeavyJob).to receive(:perform_later).and_return(double(job_id: 'first'), double(job_id: 'second'))
    allow(OffseasonPerformance::MixedOrdinaryJob).to receive(:perform_later)
    allow(File).to receive_messages(exist?: true, read: '{"job_id":"wrong"}')
    expect { workload.enqueue }.to raise_error('Wrong heavy readiness identity')
    expect(OffseasonPerformance::MixedOrdinaryJob).not_to have_received(:perform_later)
  end

  it 'checks readiness against a fresh monotonic clock and fails at the existing bounded timeout' do
    scenario = instance_double(OffseasonPerformance::Scenario, fixture: { 'season_id' => 1, 'model_id' => 2 })
    workload = described_class.new(scenario)
    allow(OffseasonPerformance::Telemetry).to receive(:now).and_return(0, 181)
    allow(File).to receive(:exist?).and_return(false)
    expect { workload.await_ready(double(job_id: 'first')) }.to raise_error('Mixed heavy readiness timeout')
    expect(OffseasonPerformance::Telemetry).to have_received(:now).twice
  end

  it 'polls persisted execution using a fresh deadline check on every unsuccessful iteration' do
    allow(described_class).to receive(:execution_row).with('job').and_return(nil)
    allow(OffseasonPerformance::Telemetry).to receive(:now).and_return(0, 9, 11)
    allow(described_class).to receive(:sleep)
    expect { described_class.execution('job') }.to raise_error('Missing or duplicate persisted execution evidence')
    expect(OffseasonPerformance::Telemetry).to have_received(:now).exactly(3).times
    expect(described_class).to have_received(:sleep).with(0.1).once
  end

  it 'rejects nonfinite timestamps, every nonnil error, missing process evidence and malformed argument vectors' do
    [{ 'started_at' => Float::NAN }, { 'created_at' => Float::INFINITY }, { 'error' => false }, { 'error' => '' },
     { 'process_id' => nil }, { 'arguments' => ['token', 1] }].each do |invalid|
      rows = evidence.deep_dup
      rows.first.merge!(invalid)
      expect(described_class.validate(rows, samples)).to eq(['missing persisted execution evidence'])
    end
  end

  it 'accepts ordinary start at the ten-second boundary and serial persisted heavy intervals' do
    expect(described_class.validate(evidence, samples)).to eq([])
  end

  it 'fails late ordinary work, overlapping heavy work, absent intervals and out-of-window HTTP' do
    evidence.last['started_at'] += 0.01
    evidence.last['created_at'] = 1
    expect(described_class.validate(evidence, samples)).to include('ordinary start exceeds 10s')
    evidence[1]['started_at'] = 19
    expect(described_class.validate(evidence, samples)).to include('heavy executions overlap')
    evidence.last.merge!('started_at' => 21, 'finished_at' => 22)
    expect(described_class.validate(evidence, samples)).to include('ordinary execution does not overlap first heavy')
    expect(described_class.validate([], samples)).to include('missing persisted execution evidence')
    samples.first['finished_at'] = 21
    expect(described_class.validate(evidence, samples)).to include('HTTP samples outside first heavy execution')
  end
end
