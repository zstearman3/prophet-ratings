# frozen_string_literal: true

require 'json'
require 'digest'
require 'time'
require_relative 'budgets'
require_relative 'scenario'
require_relative 'run_options'
require_relative 'run_verdict'
require_relative 'docker_run'
require_relative 'docker_setup'
require_relative 'container_sampler'
require_relative 'phase_runner'

module OffseasonPerformance
  # Coordinates standalone runs while leaving application code, maintainer services and data untouched.
  class Runner
    SCENARIOS = %w[dashboard readiness departures preseason status preview publish cbbd compare schedule solver mixed].freeze
    GETS = Scenario::GETS

    def initialize(argv)
      @options = RunOptions.parse(argv)
      @run = DockerRun.new(@options)
      @result = { 'schema_version' => 1, 'owner' => @run.owner, 'scale' => @options.fetch(:scale),
                  'started_at' => Time.now.utc.iso8601, 'scenarios' => [], 'errors' => [],
                  'container_windows' => [], 'limitations' => Runner.limitations }
    end

    def call
      execute
    rescue StandardError, Interrupt => error
      @result['errors'] << "#{error.class}: #{error.message}"
    ensure
      finalize
    end

    def execute
      capture_host
      prepare
      scenarios.each { |scenario| run_scenario(scenario) }
    end

    def finalize
      @result['completed_at'] = Time.now.utc.iso8601
      @result['coverage'] = RunVerdict.coverage(@result, scenarios)
      capture_setup_db
      cleanup
      write_result
    end

    def write_result
      @result['pass'] = RunVerdict.passed?(@result)
      File.write(@run.output, JSON.pretty_generate(@result))
    end

    def exit_code
      RunVerdict.exit_code(@result, @options)
    end

    def self.limitations
      ['GC deltas are process-wide and overlap at concurrency 3; never sum as exclusive attribution.',
       'Memory peak is since container boot and includes setup between publish samples and Python children.',
       'PostgreSQL memory/CPU and SQL wall time are reported separately; local shared-host contention is not controlled.',
       'Fresh boot excludes authentication and boot time; TCP readiness performs no application HTTP requests.',
       'No forced GC or restarts within any warmup plus measured sequence.']
    end

    private

    def capture_host
      @result['host'] = { 'ruby' => RUBY_DESCRIPTION, 'platform' => RUBY_PLATFORM,
                          'docker_version' => @run.command('docker', 'version', '--format', '{{json .}}'),
                          'compose_version' => @run.command('docker', 'compose', 'version'),
                          'docker_info' => @run.command('docker', 'info', '--format', '{{json .}}'),
                          'contention' => @run.command('docker', 'ps', '--format', '{{json .}}'),
                          'source_sha' => @run.command('git', 'rev-parse', 'HEAD').strip,
                          'source_diff_sha256' => Digest::SHA256.hexdigest(@run.command('git', 'diff', 'HEAD')),
                          'dependency_sha256' => Digest::SHA256.hexdigest(File.read('Gemfile.lock') + File.read('Dockerfile.dev')),
                          'source_files_sha256' => source_files }
    end

    def source_files
      files = @run.command('git', 'ls-files', '--cached', '--others', '--exclude-standard').lines.map(&:strip)
      files.sort.filter_map do |path|
        [path, Digest::SHA256.file(path).hexdigest] if File.file?(path)
      end.to_h
    end

    def prepare
      DockerSetup.new(@run, @result).call
    end

    def scenarios
      selected = @options[:scenario]
      selected ? [selected] : SCENARIOS
    end

    def run_scenario(scenario)
      phases = GETS.include?(scenario) ? %w[serial concurrent] : ['serial']
      phases.each { |phase| PhaseRunner.new(@run, @result, { scenario:, phase: }).call }
    end

    def capture_setup_db
      @result.merge!(@run.postgres_counters)
    rescue StandardError => error
      @result['errors'] << "Cannot capture final PostgreSQL counters: #{error.message}"
    end

    def cleanup
      @run.cleanup
    rescue StandardError => error
      @result['errors'] << "Owned cleanup failed: #{error.message}; project #{@run.owner}"
    end
  end
end
