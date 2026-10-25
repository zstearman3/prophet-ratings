# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require Rails.root.join('script/performance/runner')

RSpec.describe OffseasonPerformance::Runner do
  it 'persists a fail-closed result and cleans up only its owned project after setup errors' do
    Dir.mktmpdir do |directory|
      output = File.join(directory, 'result.json')
      runner = described_class.new(['--scenario', 'solver', '--output', output])
      allow(runner).to receive(:capture_host)
      allow(runner).to receive(:prepare).and_raise('synthetic setup failure')
      allow(runner).to receive(:cleanup)
      allow(runner).to receive(:capture_setup_db)
      runner.call
      result = JSON.parse(File.read(output))
      expect(result).to include('pass' => false, 'coverage' => { 'solver' => 'incomplete' })
      expect(result['owner']).to match(/\Aoffseason-[a-f0-9]+\z/)
      expect(runner).to have_received(:cleanup)
      expect(runner.exit_code).to eq(2)
    end
  end

  it 'rejects unsupported scales before creating resources' do
    expect { described_class.new(['--scale', '3']) }.to raise_error(ArgumentError, 'scale must be 1 or 2')
  end
end
