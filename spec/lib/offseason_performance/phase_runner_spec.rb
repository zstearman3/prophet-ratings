# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require Rails.root.join('script/performance/runner')

RSpec.describe OffseasonPerformance::PhaseRunner do
  it 'removes the old sampler only after its container can no longer write another stale sample' do
    Dir.mktmpdir do |directory|
      run = instance_double(OffseasonPerformance::DockerRun, env: {}, directory:)
      path = File.join(directory, 'worker-current.json')
      allow(run).to receive(:compose).with('rm', '-s', '-f', 'web', 'worker') { File.write(path, 'old sample') }
      phase = described_class.new(run, {}, { scenario: 'status', phase: 'serial' })
      allow(phase).to receive(:boot) { expect(File.exist?(path)).to be(false) }
      phase.restart
      expect(run.env.fetch('BENCHMARK_PHASE')).to eq('status-serial')
    end
  end
end
