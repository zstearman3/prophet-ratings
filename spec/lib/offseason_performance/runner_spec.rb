# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require 'open3'
require Rails.root.join('script/performance/runner')

RSpec.describe OffseasonPerformance::Runner do
  let(:native_finalization_probe) do
    <<~RUBY
      require File.expand_path('script/performance/runner', Dir.pwd)
      abort 'Rails was loaded' if defined?(Rails)
      phases = %w[validate old-serial old-concurrent draft-serial draft-concurrent status confirm publish revalidate]
      rows = phases.map { |phase| { 'scenario' => 'departure_validation', 'phase' => phase, 'failures' => [] } }
      windows = phases.flat_map do |phase|
        %w[web worker].map do |role|
          { 'scenario' => 'departure_validation', 'phase' => phase, 'container' => role,
            'state' => { 'OOMKilled' => false }, 'failures' => [] }
        end
      end
      resource = Struct.new(:output, :cleanup_calls) do
        def postgres_counters
          {}
        end

        def cleanup
          self.cleanup_calls += 1
        end
      end.new(ARGV.fetch(0), 0)
      runner = OffseasonPerformance::Runner.allocate
      runner.instance_variable_set(:@run, resource)
      runner.instance_variable_set(:@options, { scenario: 'departure_validation', assert: true })
      runner.instance_variable_set(:@result, { 'scenarios' => rows, 'container_windows' => windows, 'errors' => [] })
      runner.define_singleton_method(:execute) {}
      runner.call
      result = JSON.parse(File.read(resource.output))
      abort 'Cleanup was not called exactly once' unless resource.cleanup_calls == 1
      abort 'Nine-phase coverage was incomplete' unless result.fetch('coverage') == { 'departure_validation' => 'measured' }
      abort 'Final verdict failed' unless result.fetch('pass') && result.fetch('completed_at') && runner.exit_code.zero?
      invalid = result.merge('scenarios' => rows.map(&:dup))
      invalid.fetch('scenarios').last['phase'] = 'validate'
      coverage = OffseasonPerformance::RunVerdict.coverage(invalid, ['departure_validation'])
      abort 'Duplicate phase accepted' unless coverage == { 'departure_validation' => 'incomplete' }
      failed = result.merge('pass' => false, 'scenarios' => rows.map(&:dup))
      failed.fetch('scenarios').first['failures'] = ['p95 exceeds 1s']
      verdict = OffseasonPerformance::RunVerdict
      abort 'Budget breach accepted' if verdict.passed?(failed) || verdict.exit_code(failed, { assert: true }) != 1
      abort 'Rails was loaded during finalization' if defined?(Rails)
      puts 'Native nine-phase finalization: cleanup=1, verdict=pass, exit=0, Rails absent'
    RUBY
  end

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

  it 'loads the standalone CLI and displays help without Rails or Docker setup', :aggregate_failures do
    output, error, status = Open3.capture3(RbConfig.ruby, 'bin/benchmark-offseason', '--help', chdir: Rails.root.to_s)
    expect(status.success?).to be(true), error
    expect(output).to include('Usage: bin/benchmark-offseason')
    probe = "require_relative './script/performance/runner'; abort 'Rails was loaded' if defined?(Rails)"
    _output, error, status = Open3.capture3(RbConfig.ruby, '-e', probe, chdir: Rails.root.to_s)
    expect(status.success?).to be(true), error
  end

  it 'finalizes all nine phases and cleans up without Rails in a fresh native process' do
    Dir.mktmpdir do |directory|
      output, error, status = Open3.capture3(RbConfig.ruby, '-e', native_finalization_probe, File.join(directory, 'result.json'),
                                             chdir: Rails.root.to_s)
      expect(status.success?).to be(true), "#{error}\n#{output}"
    end
  end

  it 'rejects unsupported scales before creating resources' do
    expect { described_class.new(['--scale', '3']) }.to raise_error(ArgumentError, 'scale must be 1 or 2')
  end
end
