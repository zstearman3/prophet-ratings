# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/performance/driver')

RSpec.describe OffseasonPerformance::JobDriver do
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
