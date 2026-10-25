# frozen_string_literal: true

require 'rails_helper'
require 'open3'
require 'tmpdir'
require 'yaml'

RSpec.describe 'ECS migration deployment gate' do # rubocop:disable RSpec/DescribeClass
  let(:sandbox) { Dir.mktmpdir('ecs-migration-spec-') }
  let(:task_arn) { 'arn:aws:ecs:us-east-1:123456789012:task/test/migration' }
  let(:launch) { { tasks: [{ taskArn: task_arn, containers: [{ name: 'migration' }] }], failures: [] } }
  let(:task) do
    { taskArn: task_arn, lastStatus: 'STOPPED', stopCode: 'EssentialContainerExited',
      containers: [{ name: 'migration', lastStatus: 'STOPPED', exitCode: 0 }] }
  end
  let(:description) { { tasks: [task], failures: [] } }
  let(:steps) { YAML.load_file(Rails.root.join('.github/workflows/deploy.yml')).dig('jobs', 'deploy', 'steps') }
  let(:environment) do
    { 'PATH' => "#{sandbox}:#{ENV.fetch('PATH')}", 'RUBYOPT' => nil,
      'COMMAND_LOG' => File.join(sandbox, 'calls'), 'LAUNCH' => launch.to_json, 'DESCRIPTION' => description.to_json }
  end

  before do
    File.write(File.join(sandbox, 'aws'), <<~FAKE)
      #!/usr/bin/env ruby
      require 'json'
      File.open(ENV.fetch('COMMAND_LOG'), 'a') { |file| file.puts(ARGV.to_json) }
      command = ARGV.fetch(1)
      exit 23 if ENV['FAIL_COMMAND'] == command
      case command
      when 'run-task' then puts ENV.fetch('LAUNCH')
      when 'describe-tasks' then puts ENV.fetch('DESCRIPTION')
      when 'wait', 'update-service' then exit 0
      else abort 'Unexpected AWS command'
      end
    FAKE
    File.chmod(0o755, File.join(sandbox, 'aws'))
  end

  after { FileUtils.remove_entry(sandbox) }

  def deploy(env = {})
    script = steps.filter_map { |step| step['run'] if step['name'].match?(/migrations|Redeploy/) }.join("\n")
    Open3.capture3(environment.merge(env), 'bash', '-e', '-o', 'pipefail', '-c', script, chdir: Rails.root)
  end

  def commands
    File.readlines(File.join(sandbox, 'calls')).map { |line| JSON.parse(line) }
  end

  it 'waits for and verifies the exact task before updating either service', :aggregate_failures do
    expect(deploy.last).to be_success
    expect(commands.pluck(1)).to eq(%w[run-task wait describe-tasks update-service update-service])
    expect(commands[1]).to include('tasks-stopped', task_arn, '--cluster', 'prophet-cluster', '--region', 'us-east-1')
    expect(commands[2]).to include(task_arn)
    expect(steps.select { |step| step['name'].start_with?('Redeploy') }.all? { |step| !step['if'] }).to be true
  end

  it 'rejects placement failures even if the API call itself succeeds', :aggregate_failures do
    launch[:failures] = [{ reason: 'RESOURCE:MEMORY' }]
    expect(deploy.last).not_to be_success
    expect(commands.pluck(1)).to eq(['run-task'])
  end

  it 'rejects a launch without a task', :aggregate_failures do
    launch[:tasks] = []
    expect(deploy.last).not_to be_success
    expect(commands.pluck(1)).to eq(['run-task'])
  end

  %w[run-task wait describe-tasks].each do |failed_command|
    it "blocks rollout when #{failed_command} fails", :aggregate_failures do
      expect(deploy('FAIL_COMMAND' => failed_command).last).not_to be_success
      expect(commands.pluck(1)).not_to include('update-service')
    end
  end

  [1, 137, nil].each do |exit_code|
    it "blocks rollout for migration exit code #{exit_code.inspect}", :aggregate_failures do
      task[:containers][0][:exitCode] = exit_code
      output, error, status = deploy
      expect(status).not_to be_success
      expect(output + error).to include(task_arn, 'migration')
      expect(commands.pluck(1)).not_to include('update-service')
    end
  end

  it 'rejects missing or mismatched task/container results and abnormal stops', :aggregate_failures do
    invalid_tasks = [[], [task.merge(taskArn: 'wrong')], [task.merge(containers: [])],
                     [task.merge(containers: [{ name: 'sidecar', lastStatus: 'STOPPED', exitCode: 0 }])],
                     [task.merge(lastStatus: 'RUNNING')], [task.merge(stopCode: 'TaskFailedToStart')]]
    invalid_tasks.each do |tasks|
      expect(deploy('DESCRIPTION' => { tasks: tasks, failures: [] }.to_json).last).not_to be_success
    end
    expect(deploy('DESCRIPTION' => { tasks: [task], failures: [{ reason: 'MISSING' }] }.to_json).last).not_to be_success
    expect(commands.pluck(1)).not_to include('update-service')
  end
end
