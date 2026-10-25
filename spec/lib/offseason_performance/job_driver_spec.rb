# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/performance/driver')

RSpec.describe OffseasonPerformance::JobDriver do
  it 'waits for the matching serialized comparison pin before reading its new artifact' do
    scenario = instance_double(OffseasonPerformance::Scenario, queued?: false, fixture: { 'cbbd_id' => 1 })
    driver = described_class.new(scenario)
    identity = [1, { 'evidence_digest' => 'retained', 'active_comparison_id' => 2, 'draft_revision' => 3 }]
    job = double(active_job_id: 'job', serialized_params: { 'arguments' => ActiveJob::Arguments.serialize(identity) })
    allow(driver).to receive(:new_job).with(0).and_return(job)
    events = []
    allow(described_class).to receive(:wait_job).with('job') {
      events << 'finished'
      { 'terminal' => 'performed' }
    }
    allow(described_class).to receive(:comparison).with(2, 1) {
      events << 'artifact'
      4
    }
    state = { 'comparison_identity' => identity, 'before_job' => 0, 'before_comparison' => 2 }
    expect(driver.complete({}, state)).to include('comparison_id' => 4, 'worker' => { 'terminal' => 'performed' })
    expect(events).to eq(%w[finished artifact])
  end

  it 'never accepts the next comparison artifact when the serialized job pin differs' do
    scenario = instance_double(OffseasonPerformance::Scenario, queued?: false)
    driver = described_class.new(scenario)
    allow(driver).to receive(:new_job).and_return(double(active_job_id: 'job', serialized_params: { 'arguments' => [1, 'wrong'] }))
    allow(described_class).to receive(:wait_job).and_return('terminal' => 'performed')
    allow(described_class).to receive(:comparison)
    state = { 'comparison_identity' => [1, 'expected'], 'before_job' => 0, 'before_comparison' => 2 }
    expect { driver.complete({}, state) }.to raise_error('Comparison pin mismatch')
    expect(described_class).not_to have_received(:comparison)
  end

  it 'reports a failed job when telemetry has no terminal marker' do
    expect { described_class.verify_job_output({ 'job_class' => 'PreviewPreseasonJob' }, 'job-id') }
      .to raise_error(RuntimeError, 'Job failed job-id')
  end

  it 'requires successful terminal output byte telemetry rather than accepting a missing scalar' do
    expect { described_class.verify_job_output({ 'terminal' => 'performed' }, 'job-id') }.to raise_error(/Missing job output bytes/)
    expect { described_class.verify_job_output({ 'terminal' => 'performed', 'output_bytes' => 0 }, 'job-id') }.not_to raise_error
    expect { described_class.verify_job_output({ 'terminal' => 'failed', 'output_bytes' => 127 }, 'job-id') }.to raise_error(/Job failed/)
  end
end
