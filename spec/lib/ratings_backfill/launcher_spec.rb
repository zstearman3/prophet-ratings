# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'
require 'timeout'
require_relative '../../../lib/ratings_backfill/launcher'

RSpec.describe RatingsBackfill::Launcher do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:sandbox) { Dir.mktmpdir('ratings-backfill-spec-') }
  let(:command_log) { File.join(sandbox, 'commands.jsonl') }
  # Standalone CLI/fake executables need no inherited Bundler preload on every subprocess.
  let(:environment) do
    { 'RUBYOPT' => nil, 'PATH' => "#{sandbox}:#{ENV.fetch('PATH')}", 'COMMAND_LOG' => command_log,
      'COMPOSE_PROJECT_NAME' => 'backfill-spec', 'FAKE_PLAN' => plan.to_json }
  end
  let(:plan) do
    { season_id: 12, model_id: 34, model: 'baseline', year: 2025, season_start: '2024-11-01', season_end: '2025-04-07',
      from: '2024-11-01', through: '2024-11-18', next_date: '2024-11-04', cohort_key: 'stored-cohort',
      initialize_preseason: false, completed_days: 3, total_days: 18 }
  end

  before do
    File.write(File.join(sandbox, 'docker'), fake_docker)
    File.chmod(0o755, File.join(sandbox, 'docker'))
  end

  after { FileUtils.remove_entry(sandbox) }

  def fake_docker
    <<~RUBY
      #!/usr/bin/env ruby
      require 'json'
      require 'tmpdir'
      payload = ARGV.find { |arg| arg.start_with?('BACKFILL_REQUEST=') }
      request = JSON.parse(payload.split('=', 2).last) if payload
      override = ARGV.each_cons(2).filter_map { |flag, path| File.read(path) if flag == '-f' && path.start_with?(Dir.tmpdir) }
      File.open(ENV.fetch('COMMAND_LOG'), 'a') do |file|
        file.puts({ args: ARGV, request: request, override: override, cwd: Dir.pwd }.to_json)
      end
      if ARGV == ['info']
        warn 'Cannot connect to Docker daemon' if ENV['FAKE_DOCKER_DOWN']
        exit 1 if ENV['FAKE_DOCKER_DOWN']
      elsif ARGV.include?('run')
        name = ARGV[ARGV.index('--name') + 1]
        File.write(File.join(File.dirname(ENV.fetch('COMMAND_LOG')), name), Process.pid.to_s)
        if request.fetch('phase') == 'plan'
          puts 'BACKFILL_PLAN ' + ENV.fetch('FAKE_PLAN') unless ENV['FAKE_NO_PLAN']
          puts 'BACKFILL_PLAN ' + ENV.fetch('FAKE_PLAN') if ENV['FAKE_DUPLICATE_PLAN']
          exit ENV.fetch('FAKE_PLAN_EXIT', '0').to_i
        else
          STDOUT.sync = true
          puts '[backfill] starting ' + request.fetch('from')
          warn 'child diagnostic'
          if ENV['FAKE_WAIT']
            trap('TERM') { exit 143 }
            sleep 60
          end
          sleep ENV.fetch('FAKE_SLEEP', '0').to_f
          exit ENV.fetch('FAKE_RUN_EXIT', '0').to_i
        end
      elsif ARGV.first == 'stop'
        pid = File.read(File.join(File.dirname(ENV.fetch('COMMAND_LOG')), ARGV.last)).to_i
        Process.kill('TERM', pid)
      elsif ARGV.first == 'stats'
        puts '128MiB / 1GiB 12.5%'
      elsif ARGV.first == 'inspect'
        puts ENV.fetch('FAKE_OOM', 'false')
      end
    RUBY
  end

  def run_launcher(*, env: {})
    Open3.capture3(environment.merge(env), File.join(root, 'bin/backfill-ratings'),
                   '--year', '2025', '--model', 'baseline', *)
  end

  def commands
    File.readlines(command_log).map { |line| JSON.parse(line) }
  end

  def runs
    commands.select { |command| command['request'] }
  end

  def windows
    runs.drop(1).map { |command| command.fetch('request').values_at('from', 'through') }
  end

  it 'resumes bounded windows through the Rails boundary and cleans up only its unique containers', :aggregate_failures do
    plan.merge!(range_start: '2024-11-01', range_end: '2024-11-18', extra_metadata: 'future-proof')
    output, errors, status = run_launcher
    expect(status).to be_success
    expect(windows).to eq([%w[2024-11-04 2024-11-10], %w[2024-11-11 2024-11-17], %w[2024-11-18 2024-11-18]])
    expect(runs.drop(1).map { |command| command['request']['model_id'] }).to eq([34, 34, 34])
    expect(output).to include('backfill-spec', '3/18', '[backfill] starting', 'Backfill complete')
    names = runs.map { |command| command['args'][command['args'].index('--name') + 1] }
    expect(names.uniq.size).to eq(4)
    expect(commands.select { |command| command['args'].first == 'rm' }.map { |command| command['args'].last }).to eq(names)
    expect(runs).to all(include('cwd' => root))
    expect(errors).to include('child diagnostic')
    expected = { 'range_start' => '2024-11-01', 'range_end' => '2024-11-18',
                 'cohort_key' => 'stored-cohort', 'extra_metadata' => 'future-proof' }
    expect(runs.drop(1).map { |command| command.fetch('request') }).to all(include(expected))
    runs.each do |command|
      expect(command['args']).to include('--no-deps', '-T', 'web', 'bin/rails', 'runner', 'script/ratings_backfill_chunk.rb')
      expect(command['args']).not_to include('--rm', 'build', 'up', 'down')
      expect(command['args'].index('-e')).to be < command['args'].index('web')
    end
  end

  it 'passes explicit scope and initializes preseason only on the first chunk' do
    plan[:initialize_preseason] = true
    _, _, status = run_launcher('--from', '2024-11-01', '--through', '2024-11-18', '--initialize-preseason', '--chunk-days', '5')
    expect(status).to be_success
    expect(runs.first['request']).to include('from' => '2024-11-01', 'through' => '2024-11-18', 'initialize_preseason' => true)
    expect(windows.size).to eq(3)
    expect(runs.drop(1).map { |command| command['request']['initialize_preseason'] }).to eq([true, false, false])
  end

  it 'exits without running chunks when the stored range is complete' do
    plan[:next_date] = nil
    output, _, status = run_launcher
    expect(status).to be_success
    expect(runs.size).to eq(1)
    expect(output).to include('already complete')
  end

  it 'stops at a failed chunk, preserves its exit status and retains the container' do
    _, errors, status = run_launcher(env: { 'FAKE_RUN_EXIT' => '137', 'FAKE_OOM' => 'true' })
    expect(status.exitstatus).to eq(137)
    expect(runs.size).to eq(2)
    expect(commands.count { |command| command['args'].first == 'rm' }).to eq(1)
    expect(errors).to include('OOMKilled=true', 'docker logs', 'Completed days persist', 'rerun the same command')
  end

  it 'reports periodic elapsed time and memory for the owned child only' do
    plan[:through] = '2024-11-10'
    output, _, status = run_launcher('--progress-seconds', '0.05', env: { 'FAKE_SLEEP' => '0.2' })
    expect(status).to be_success
    expect(output).to include('elapsed=', '2024-11-04..2024-11-10', '128MiB / 1GiB 12.5%')
    stats = commands.select { |command| command['args'].first == 'stats' }
    expect(stats).not_to be_empty
    names = runs.map { |command| command['args'][command['args'].index('--name') + 1] }
    expect(stats.map { |command| command['args'].last } - names).to be_empty
  end

  it 'applies the optional memory cap with a temporary compose override' do
    plan[:through] = '2024-11-10'
    _, _, status = run_launcher('--project', 'custom-project', '--memory', '1g')
    expect(status).to be_success
    expect(runs.first['override']).to eq(["services:\n  web:\n    mem_limit: 1g\n"])
    expect(runs.first['args'].first(3)).to eq(%w[compose --project-name custom-project])
    overrides = runs.first['args'].each_cons(2).filter_map { |flag, path| path if flag == '-f' && path.start_with?(Dir.tmpdir) }
    expect(overrides).not_to be_empty
    expect(overrides.none? { |path| File.exist?(path) }).to be true
  end

  it 'reports unavailable Docker without starting a container' do
    _, errors, status = run_launcher(env: { 'FAKE_DOCKER_DOWN' => '1' })
    expect(status).not_to be_success
    expect(errors).to include('Docker', 'Cannot connect')
    expect(runs).to be_empty
  end

  it 'rejects successful child output without a plan marker' do
    _, errors, status = run_launcher(env: { 'FAKE_NO_PLAN' => '1' })
    expect(status).not_to be_success
    expect(errors).to include('BACKFILL_PLAN')
    expect(runs.size).to eq(1)
  end

  it 'retains a planning container that refuses an overlapping backfill without starting chunks' do
    _, errors, status = run_launcher(env: { 'FAKE_PLAN_EXIT' => '23' })
    expect(status.exitstatus).to eq(23)
    expect(runs.size).to eq(1)
    expect(commands.none? { |command| command['args'].first == 'rm' }).to be true
    expect(errors).to include('Retained:')
  end

  it 'requires exactly one planning marker' do
    _, errors, status = run_launcher(env: { 'FAKE_DUPLICATE_PLAN' => '1' })
    expect(status).not_to be_success
    expect(runs.size).to eq(1)
    expect(errors).to include('exactly one BACKFILL_PLAN')
  end

  ['[]', 'null', '{bad'].each do |invalid|
    it "reports an invalid plan without running chunks or a Ruby backtrace: #{invalid}" do
      _, errors, status = run_launcher(env: { 'FAKE_PLAN' => invalid })
      expect(status).not_to be_success
      expect(runs.size).to eq(1)
      expect(errors).to include('[backfill]')
      expect(errors).not_to include('chunk_plan.rb:')
    end
  end

  it 'shows help without requiring a model, year or Docker' do
    output, errors, status = Open3.capture3(environment, File.join(root, 'bin/backfill-ratings'), '--help')
    expect(status).to be_success
    expect(output).to include('--year', '--model', '--chunk-days', '--memory')
    expect(errors).to be_empty
    expect(File.exist?(command_log)).to be false
  end

  it 'requires a model and year before contacting Docker' do
    _, errors, status = Open3.capture3(environment, File.join(root, 'bin/backfill-ratings'))
    expect(status).not_to be_success
    expect(errors).to include('--year and --model are required')
    expect(File.exist?(command_log)).to be false
  end

  %w[INT TERM].each do |signal|
    it "stops only its current child container on #{signal} and retains it for inspection" do
      status = nil
      Open3.popen3(environment.merge('FAKE_WAIT' => '1'), File.join(root, 'bin/backfill-ratings'),
                   '--year', '2025', '--model', 'baseline') do |stdin, stdout, _, process|
        stdin.close
        Timeout.timeout(10) { loop { break if stdout.gets&.include?('[backfill] starting') } }
        Process.kill(signal, process.pid)
        status = Timeout.timeout(10) { process.value }
      ensure
        Process.kill('KILL', process.pid) if process.alive?
      end
      expect(status.exitstatus).to eq(128 + Signal.list.fetch(signal))
      stopped = commands.select { |command| command['args'].first == 'stop' }
      expect(stopped.size).to eq(1)
      expect(stopped.first['args'].last).to eq(runs.last['args'][runs.last['args'].index('--name') + 1])
      expect(commands.count { |command| command['args'].first == 'rm' }).to eq(1)
    end
  end

  ['--chunk-days 0', '--progress-seconds -1', '--memory 1g;bad', '--from 2024-02-30', '--year nope',
   '--progress-seconds 0', '--chunk-days 1.5', '--project Invalid',
   '--from 2024-11-19 --through 2024-11-18'].each do |invalid|
    it "rejects invalid arguments before touching Docker: #{invalid}" do
      original_sync = $stdout.sync
      allow(RatingsBackfill::DockerClient).to receive(:new).and_raise('Invalid arguments reached Docker')
      status = nil
      expect do
        status = described_class.new(['--year', '2025', '--model', 'baseline', *invalid.split]).call
      end.to output(/\S/).to_stderr
      expect(status).to eq(1)
      expect(RatingsBackfill::DockerClient).not_to have_received(:new)
      expect(File.exist?(command_log)).to be false
    ensure
      $stdout.sync = original_sync
    end
  end
end
