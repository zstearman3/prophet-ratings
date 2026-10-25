# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require Rails.root.join('script/performance/runner')

RSpec.describe OffseasonPerformance::DockerRun do
  it 'cleans only the randomly owned project, volumes and image tags' do
    Dir.mktmpdir do |directory|
      run = described_class.new(scale: 1, output: File.join(directory, 'result.json'))
      allow(run).to receive(:command)
      run.cleanup
      expect(run).to have_received(:command).with('docker', 'compose', '-p', run.owner, '-f', 'compose.performance.yml',
                                                  'down', '--volumes', '--remove-orphans', '--timeout', '10')
      expect(run).to have_received(:command).with('docker', 'image', 'rm', "#{run.owner}:local", "#{run.owner}-base:local")
      expect(File.read(File.join(run.directory, 'owner'))).to eq(run.owner)
    end
  end

  it 'reports a failed project teardown and still attempts exact owned image cleanup' do
    Dir.mktmpdir do |directory|
      run = described_class.new(scale: 1, output: File.join(directory, 'result.json'))
      allow(run).to receive(:command)
      allow(run).to receive(:command).with('docker', 'compose', '-p', run.owner, '-f', 'compose.performance.yml',
                                           'down', '--volumes', '--remove-orphans', '--timeout', '10').and_raise('down failed')
      expect { run.cleanup }.to raise_error(/Owned cleanup commands failed: down failed/)
      expect(run).to have_received(:command).with('docker', 'image', 'rm', "#{run.owner}:local", "#{run.owner}-base:local")
    end
  end

  it 'keeps signal exits as failures rather than treating nil exit status as success' do
    data = { exit: nil, stderr: 'terminated', argv: %w[docker example] }
    expect { described_class.verify_command(data, {}) }.to raise_error(/Command failed/)
    expect { described_class.verify_command(data, allow_failure: true) }.not_to raise_error
  end
end
