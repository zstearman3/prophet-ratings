# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationJob do
  let(:job_class) do
    Class.new(described_class) do
      def perform
        raise StandardError, 'job failed'
      end
    end
  end

  it 'retries failures before the fifth execution' do
    job = job_class.new
    allow(job).to receive(:retry_job)

    expect { job.perform_now }.not_to raise_error
    expect(job).to have_received(:retry_job)
  end

  it 'stops retrying after five executions' do
    job = job_class.new
    job.exception_executions[[StandardError].to_s] = described_class::MAX_EXECUTIONS - 1
    allow(job).to receive(:retry_job)

    expect { job.perform_now }.to raise_error(StandardError, 'job failed')
    expect(job).not_to have_received(:retry_job)
  end

  it 'turns off GoodJob unlimited retries for unhandled errors' do
    expect(Rails.application.config.good_job.retry_on_unhandled_error).to be(false)
  end
end
