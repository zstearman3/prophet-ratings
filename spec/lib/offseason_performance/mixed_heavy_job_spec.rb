# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/performance/telemetry')
require Rails.root.join('script/performance/driver')
require Rails.root.join('script/performance/solver_job')
require Rails.root.join('script/performance/mixed_jobs')

RSpec.describe OffseasonPerformance::MixedHeavyJob do
  before { allow(File).to receive(:exist?).and_call_original }

  it 'keeps the complete matrix and both coefficient vectors in the verified operand set' do
    expected = Array.new(730) { |index| index.even? ? 2.0 : -3.0 }
    allow(StatisticsUtils).to receive(:solve_least_squares_with_python).and_return(expected)
    operands = described_class.solution
    expect(described_class.dimensions(operands)).to eq(rows: 1460, columns: 730)
    expect(operands).to include(expected:, actual: expected, error: 0)
    expect(StatisticsUtils).to have_received(:solve_least_squares_with_python).with(operands.fetch(:matrix), expected * 2, ridge_alpha: 0)
  end

  it 'retains the ten-second minimum hold even when the driver already released work' do
    job = described_class.new
    allow(OffseasonPerformance::Telemetry).to receive(:now).and_return(9.9, 10.0)
    allow(File).to receive(:exist?).with('/benchmark/mixed-release-token').and_return(true)
    allow(job).to receive(:sleep)
    job.hold('token', 0)
    expect(job).to have_received(:sleep).with(0.1).once
    expect(OffseasonPerformance::Telemetry).to have_received(:now).twice
  end

  it 'keeps the bounded hold failure when the driver never releases work' do
    allow(OffseasonPerformance::Telemetry).to receive(:now).and_return(121)
    allow(File).to receive(:exist?).with('/benchmark/mixed-release-token').and_return(false)
    expect { described_class.new.hold('token', 0) }.to raise_error('Mixed workload driver did not release held work')
  end
end
