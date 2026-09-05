# frozen_string_literal: true

require 'rails_helper'
require 'open3'
require 'tmpdir'
require 'timeout'

# These integration specs exercise shell executables rather than a Ruby class.
RSpec.describe 'Development commands' do # rubocop:disable RSpec/DescribeClass
  let(:sandbox) { Dir.mktmpdir('prophet-command-spec-') }
  let(:command_log) { File.join(sandbox, 'commands.jsonl') }
  let(:environment) do
    { 'PATH' => "#{sandbox}:#{ENV.fetch('PATH')}", 'COMMAND_LOG' => command_log,
      'COMPOSE_PROJECT_NAME' => 'prophet-command-spec', 'TEST_DATABASE_URL' => 'postgresql://invalid.example/development' }
  end

  before do
    %w[docker bundle].each do |command|
      path = File.join(sandbox, command)
      File.write(path, fake_command)
      File.chmod(0o755, path)
    end
  end

  after do
    FileUtils.remove_entry(sandbox)
  end

  def fake_command
    <<~RUBY
      #!/usr/bin/env ruby
      require 'json'
      command = File.basename($PROGRAM_NAME)
      File.open(ENV.fetch('COMMAND_LOG'), 'a') do |file|
        file.puts({ command:, args: ARGV, database: ENV['TEST_DATABASE_URL'], rails_env: ENV['RAILS_ENV'] }.to_json)
      end
      if command == 'docker'
        exit 1 if ARGV == ['info'] && ENV['FAKE_DOCKER_DOWN']
        exit 19 if ARGV.include?('up') && ENV['FAKE_START_FAILURE']
        puts '127.0.0.1:65432' if ARGV.include?('port')
        exit ENV.fetch('FAKE_TEST_EXIT', '0').to_i if ARGV.include?('run')
      elsif ARGV.include?('rspec')
        if ENV['FAKE_WAIT']
          STDOUT.sync = true
          puts 'spec-ready'
          sleep 60
        end
        exit ENV.fetch('FAKE_TEST_EXIT', '0').to_i
      end
    RUBY
  end

  def run_script(name, *, env: {})
    Open3.capture3(environment.merge(env), Rails.root.join('bin', name).to_s, *).last
  end

  def commands
    File.readlines(command_log).map { |line| JSON.parse(line) }
  end

  def cleanup_command
    commands.find { |command| command['args'].include?('down') }
  end

  it 'runs only the test service, forwards RSpec arguments and removes its disposable project' do
    expect(run_script('test', 'spec/models/team_spec.rb', '--seed', '7')).to be_success

    test_run = commands.find { |command| command['args'].include?('run') }
    expect(test_run['args']).to include('--rm', '--no-deps', '-T', 'test')
    expect(test_run['args'].last(3)).to eq(['spec/models/team_spec.rb', '--seed', '7'])
    expect(cleanup_command['args']).to include('--volumes')
    expect(cleanup_command['args'][2]).to match(/\Aprophet-ratings-test-\d+-\d+\z/)
  end

  it 'gives native specs a dedicated test URL using the assigned port' do
    expect(run_script('test', '--local')).to be_success

    specs = commands.find { |command| command['command'] == 'bundle' && command['args'].include?('rspec') }
    expect(specs['database']).to eq('postgresql://postgres:password@127.0.0.1:65432/prophet_ratings_test')
    expect(specs['rails_env']).to eq('test')
    expect(commands.none? { |command| command['args'].include?('build') }).to be true
  end

  it 'preserves a failed native spec exit status and still removes the test database' do
    expect(run_script('test', '--local', env: { 'FAKE_TEST_EXIT' => '17' }).exitstatus).to eq(17)
    expect(cleanup_command['args']).to include('--volumes')
  end

  it 'preserves a failed Docker spec exit status and still removes the test database' do
    expect(run_script('test', env: { 'FAKE_TEST_EXIT' => '17' }).exitstatus).to eq(17)
    expect(cleanup_command['args']).to include('--volumes')
  end

  it 'cleans up after database startup fails' do
    expect(run_script('test', '--local', env: { 'FAKE_START_FAILURE' => '1' }).exitstatus).to eq(19)
    expect(cleanup_command['args']).to include('--volumes')
  end

  it 'fails clearly without starting containers when Docker is unavailable' do
    expect(run_script('test', env: { 'FAKE_DOCKER_DOWN' => '1' }).exitstatus).to eq(1)
    expect(commands.pluck('args')).to eq([['info']])
  end

  it 'cleans up when a native spec run is terminated' do
    status = nil
    Open3.popen3(environment.merge('FAKE_WAIT' => '1'), Rails.root.join('bin/test').to_s, '--local') do |stdin, stdout, _, process|
      stdin.close
      Timeout.timeout(10) { loop { break if stdout.gets&.include?('spec-ready') } }
      Process.kill('TERM', process.pid)
      status = Timeout.timeout(10) { process.value }
    ensure
      Process.kill('KILL', process.pid) if process.alive?
    end

    expect(status.exitstatus).to eq(143)
    expect(cleanup_command['args']).to include('--volumes')
  end

  it 'cleans up foreground development without deleting data or images' do
    expect(run_script('dev')).to be_success
    expect(cleanup_command['args']).to include('--remove-orphans')
    expect(cleanup_command['args']).not_to include('--volumes', '--rmi')
  end

  it 'keeps an explicitly detached session running until stopped' do
    expect(run_script('dev', '--detach')).to be_success
    expect(cleanup_command).to be_nil
    expect(run_script('stop')).to be_success
    expect(cleanup_command['args']).not_to include('--volumes', '--rmi')
  end
end
