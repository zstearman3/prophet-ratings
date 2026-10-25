# frozen_string_literal: true

require 'json'
require 'open3'
require 'fileutils'
require 'securerandom'

module OffseasonPerformance
  # Owns one unique Compose project, its synthetic environment and exact cleanup boundary.
  class DockerRun
    READY_PROBE = <<~RUBY
      require 'socket'
      deadline = Time.now + 90
      loop do
        begin
          TCPSocket.new('web', 3000).close
          break
        rescue SystemCallError, SocketError
          raise if Time.now > deadline
          sleep 0.2
        end
      end
    RUBY
    ASSET_SCRIPT = "require './config/environment'; require 'rake'; Rails.application.load_tasks; " \
                   '%w[css:build javascript:build].each { |name| Rake::Task[name].clear if Rake::Task.task_defined?(name) }; ' \
                   "Rake::Task['assets:precompile'].invoke"
    attr_reader :owner, :output, :directory, :env

    def initialize(options)
      @owner = "offseason-#{SecureRandom.hex(8)}"
      @output = File.expand_path(options.fetch(:output))
      @directory = File.join(File.dirname(@output), @owner)
      @env = { 'BENCHMARK_OWNER' => @owner, 'BENCHMARK_OUTPUT' => @directory,
               'BENCHMARK_SCALE' => options.fetch(:scale).to_s, 'BENCHMARK_IMAGE' => "#{@owner}:local" }
      create_directory
    end

    def create_directory
      FileUtils.mkdir_p([@directory, 'public/assets', 'tmp', 'log'])
      File.write(File.join(@directory, 'owner'), @owner)
    end

    def command(*args, **options)
      stdout, stderr, status = Open3.capture3(@env, *args)
      data = { argv: args, exit: status.exitstatus, stdout:, stderr: }
      record_command(data)
      self.class.verify_command(data, options)
      stdout
    end

    def record_command(data)
      File.open(File.join(@directory, 'commands.log'), 'a') { |file| file.puts(JSON.generate(data)) }
    end

    def self.verify_command(data, options)
      code = data.fetch(:exit)
      successful = code&.zero? || options[:allow_failure]
      return if successful

      stderr = data.fetch(:stderr)
      raise "Command failed (#{code}): #{data.fetch(:argv).join(' ')}\n#{stderr[-1500, 1500] || stderr}"
    end

    def compose(*, **)
      command('docker', 'compose', '-p', @owner, '-f', 'compose.performance.yml', *, **)
    end

    def build_images
      command('docker', 'build', '-f', 'Dockerfile.dev', '-t', "#{@owner}-base:local", '.')
      command('docker', 'build', '-f', 'script/performance/Dockerfile', '--build-arg', "BASE_IMAGE=#{@owner}-base:local",
              '-t', @env.fetch('BENCHMARK_IMAGE'), '.')
    end

    def assets
      compose('run', '--rm', '--no-deps', '-T', 'driver', 'bash', '-c',
              'cp /compiled/* /rails/app/assets/builds/ && bundle exec rails tailwindcss:build')
      compose('run', '--rm', '--no-deps', '-T', 'driver', 'bundle', 'exec', 'ruby', '-e', ASSET_SCRIPT)
    end

    def fixture_phase(phase)
      name = "#{@owner}-fixture-#{phase}"
      compose('run', '--name', name, '--no-deps', '-T', 'driver', 'bundle', 'exec', 'ruby', 'script/performance/setup.rb', phase,
              allow_failure: true)
      JSON.parse(command('docker', 'inspect', '--format', '{{json .State}}', name))
    ensure
      command('docker', 'rm', '-f', name, allow_failure: true)
    end

    def ready
      compose('run', '--rm', '--no-deps', '-T', 'driver', 'ruby', '-e', READY_PROBE)
    end

    def postgres_counters
      id = compose('ps', '-a', '-q', 'db', allow_failure: true).strip
      return {} if id.empty?

      { 'postgres_final_state' => command('docker', 'inspect', '--format', '{{json .State}}', id, allow_failure: true),
        'postgres_final_counters' => command('docker', 'exec', id, 'sh', '-c',
                                             'cat /sys/fs/cgroup/memory.current /sys/fs/cgroup/memory.peak ' \
                                             '/sys/fs/cgroup/memory.events /sys/fs/cgroup/cpu.stat', allow_failure: true) }
    end

    def cleanup
      compose('logs', '--no-color', allow_failure: true)
      failures = [cleanup_project, cleanup_images].compact
      raise "Owned cleanup commands failed: #{failures.join('; ')}" unless failures.empty?
    end

    def cleanup_project
      compose('down', '--volumes', '--remove-orphans', '--timeout', '10')
      nil
    rescue StandardError => error
      error.message
    end

    def cleanup_images
      command('docker', 'image', 'rm', @env.fetch('BENCHMARK_IMAGE'), "#{@owner}-base:local")
      nil
    rescue StandardError => error
      error.message
    end
  end
end
