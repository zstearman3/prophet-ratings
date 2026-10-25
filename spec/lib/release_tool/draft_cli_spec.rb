# frozen_string_literal: true

require 'rails_helper'
require 'open3'
require 'tmpdir'
require Rails.root.join('lib/release_tool/draft')

RSpec.describe ReleaseTool::Draft do
  it 'shows executable CLI help without Rails, GitHub authentication or release mutations' do
    output, error, status = Open3.capture3(RbConfig.ruby, Rails.root.join('bin/release').to_s, '--help')
    expect(status).to be_success
    expect(output).to include('Usage: bin/release', '--dry-run', '--update')
    expect(error).to be_empty
  end

  it 'rejects unknown CLI arguments before invoking Git or GitHub' do
    _output, error, status = Open3.capture3(RbConfig.ruby, Rails.root.join('bin/release').to_s, '--unknown-option')
    expect(status).not_to be_success
    expect(error).to include('invalid option')
  end

  context 'with isolated Git and GitHub executables' do
    let(:sandbox) { Dir.mktmpdir('release-cli-spec-') }
    let(:command_log) { File.join(sandbox, 'commands.jsonl') }
    # Standalone CLI/fake executables need no inherited Bundler preload on every subprocess.
    let(:environment) do
      { 'RUBYOPT' => nil, 'PATH' => "#{sandbox}:#{ENV.fetch('PATH')}", 'COMMAND_LOG' => command_log, 'GH_REPO' => 'wrong/repo' }
    end

    before do
      %w[git gh].each do |name|
        path = File.join(sandbox, name)
        File.write(path, fake_command)
        File.chmod(0o755, path)
      end
    end

    after { FileUtils.remove_entry(sandbox) }

    def fake_command
      <<~RUBY
        #!/usr/bin/env ruby
        require 'json'
        command = File.basename($PROGRAM_NAME)
        notes_index = ARGV.index('--notes-file')
        File.open(ENV.fetch('COMMAND_LOG'), 'a') do |file|
          file.puts(JSON.generate(command: command, args: ARGV, gh_repo: ENV['GH_REPO'],
                                  notes: notes_index ? File.read(ARGV[notes_index + 1]) : nil))
        end
        if command == 'git'
          puts(ARGV.last.include?('development') ? 'a' * 40 : 'b' * 40) if ARGV.first == 'rev-parse'
          puts(('a' * 40) + "\\tDirect CLI fix") if ARGV.first == 'log'
        elsif ARGV.first(2) == ['repo', 'view']
          puts JSON.generate(nameWithOwner: 'owner/repo')
        end
      RUBY
    end

    def run_release(*)
      Open3.capture3(environment, RbConfig.ruby, Rails.root.join('bin/release').to_s, *)
    end

    def commands
      File.readlines(command_log).map { |line| JSON.parse(line) }
    end

    it 'runs the complete dry-run path without tag or release mutations' do
      output, error, status = run_release('--dry-run')
      expect(status).to be_success
      expect(error).to be_empty
      expect(output).to include('Direct CLI fix', 'Dry run: no tags or releases changed')
      expect(commands.none? { |row| row['args'].first(2) == %w[release create] || row['args'].first == 'push' }).to be(true)
      expect(commands.pluck('gh_repo')).to all(be_nil)
    end

    it 'passes the notes file and candidate SHA to draft creation before the tag push' do
      _output, error, status = run_release
      expect(status).to be_success
      expect(error).to be_empty
      creation = commands.find { |row| row['args'].first(2) == %w[release create] }
      expect(creation.fetch('args')).to include('--draft', '--target', 'a' * 40)
      expect(creation.fetch('notes')).to include('Direct CLI fix')
      expect(commands.last.fetch('args')).to include('push', 'origin')
    end
  end
end
