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
        puts 'database-container' if ARGV.include?('ps') && ENV['FAKE_DATABASE_RUNNING']
        puts 'template1' if ARGV.any? { |arg| arg.include?('SELECT datname FROM pg_database') } && ENV['FAKE_COLLATION_MISMATCH']
        exit 17 if ARGV.any? { |arg| arg.include?('REINDEX DATABASE') } && ENV['FAKE_REINDEX_FAILURE']
        exit ENV.fetch('FAKE_TEST_EXIT', '0').to_i if ARGV.include?('run')
      elsif ARGV.include?('db:abort_if_pending_migrations') && ENV['FAKE_PENDING_MIGRATIONS']
        exit 1
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

  it 'checks for pending migrations before running Docker specs' do
    expect(run_script('test')).to be_success
    test_run = commands.find { |command| command['args'].include?('run') }
    expect(test_run['args'].join(' ')).to include('db:schema:load db:abort_if_pending_migrations && bundle exec rspec')
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

  it 'updates the tracked schema during startup rather than redirecting the dump' do
    expect(run_script('dev')).to be_success
    migration = commands.find { |command| command['args'].include?('db:migrate') }
    expect(migration['args'].last(4)).to eq(['web', 'bin/rails', 'db:create', 'db:migrate'])
    expect(migration['args'].join(' ')).not_to include('SCHEMA=')
  end

  it 'fails before native specs when the checked-in schema leaves pending migrations' do
    expect(run_script('test', '--local', env: { 'FAKE_PENDING_MIGRATIONS' => '1' })).not_to be_success
    expect(commands.none? { |command| command['args'].include?('rspec') }).to be true
    expect(cleanup_command['args']).to include('--volumes')
  end

  it 'migrates without the server and stops only the database it started' do
    expect(run_script('migrate')).to be_success
    migration = commands.find { |command| command['args'].include?('db:migrate') }
    expect(migration['args'].last(4)).to eq(['web', 'bin/rails', 'db:create', 'db:migrate'])
    expect(migration['args']).to include('--rm', '--no-deps')
    expect(commands.last['args'].last(2)).to eq(%w[stop db])
    expect(cleanup_command).to be_nil
  end

  it 'leaves an already-running development database running after migration' do
    expect(run_script('migrate', env: { 'FAKE_DATABASE_RUNNING' => '1' })).to be_success
    expect(commands.none? { |command| command['args'].include?('stop') }).to be true
    expect(cleanup_command).to be_nil
  end

  it 'preserves migration failures and stops the database it started without removing volumes' do
    expect(run_script('migrate', env: { 'FAKE_TEST_EXIT' => '17' }).exitstatus).to eq(17)
    expect(commands.last['args'].last(2)).to eq(%w[stop db])
    expect(cleanup_command).to be_nil
  end

  it 'reindexes a mismatched local database before refreshing its version' do
    expect(run_script('repair-collation', env: { 'FAKE_COLLATION_MISMATCH' => '1' })).to be_success
    reindex = commands.index { |command| command['args'].any? { |arg| arg.include?('REINDEX DATABASE "template1"') } }
    refresh = commands.index { |command| command['args'].any? { |arg| arg.include?('REFRESH COLLATION VERSION') } }
    expect(reindex).to be < refresh
    expect(commands.last['args'].last(2)).to eq(%w[stop db])
  end

  it 'does not mark the collation refreshed after an index rebuild fails' do
    status = run_script('repair-collation', env: { 'FAKE_COLLATION_MISMATCH' => '1', 'FAKE_REINDEX_FAILURE' => '1' })
    expect(status.exitstatus).to eq(17)
    expect(commands.none? { |command| command['args'].any? { |arg| arg.include?('REFRESH COLLATION VERSION') } }).to be true
    expect(commands.last['args'].last(2)).to eq(%w[stop db])
  end

  it 'keeps an explicitly detached session running until stopped' do
    expect(run_script('dev', '--detach')).to be_success
    expect(cleanup_command).to be_nil
    expect(run_script('stop')).to be_success
    expect(cleanup_command['args']).not_to include('--volumes', '--rmi')
  end
end
