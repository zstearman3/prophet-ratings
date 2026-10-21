# frozen_string_literal: true

require 'json'
require 'open3'
require 'securerandom'
require_relative 'docker_client'
require_relative 'progress'

module RatingsBackfill
  # Runs each request in a fresh named container and forwards its live output.
  class ContainerRunner
    # Preserves the child's exit status while unwinding the launcher's cleanup.
    class ChildFailure < StandardError
      attr_reader :status

      def initialize(status)
        @status = status
        super("Backfill child exited with #{status}")
      end
    end

    attr_reader :plan_lines

    def initialize(settings)
      @settings = settings
      @plan_lines = []
      @signal = nil
      @docker = DockerClient.new
    end

    def signal(signal)
      @signal ||= signal
    end

    def run(request)
      interruption = interrupted_status
      raise ChildFailure, interruption if interruption

      run_container(request)
    end

    def self.window(request)
      phase = request.fetch('phase') { request.fetch(:phase) }
      return 'planning' if phase == 'plan'

      "#{request.fetch('from')}..#{request.fetch('through')}"
    end

    def self.child_status(status)
      status.exitstatus || (128 + status.termsig)
    end

    private

    def run_container(request)
      name = "prophet-backfill-#{Process.pid}-#{SecureRandom.hex(6)}"
      @settings.fetch(:output).write("[backfill] container=#{name} #{self.class.window(request)}\n")
      finalize(name, execute(name, request))
    end

    def command(name, request)
      flags = @settings.fetch(:compose_flags)
      [File.join(@settings.fetch(:root), 'bin/compose'), *flags, 'run', '--no-deps', '-T', '--name', name,
       '-e', "BACKFILL_REQUEST=#{JSON.generate(request)}", 'web', 'bin/rails', 'runner', 'script/ratings_backfill_chunk.rb']
    end

    def execute(name, request)
      Open3.popen3({ 'COMPOSE_PROJECT_NAME' => @settings.fetch(:project) }, *command(name, request),
                   chdir: @settings.fetch(:root)) do |stdin, stdout, stderr, process|
        stdin.close
        observe(process, stdout: stdout, stderr: stderr, name: name, label: self.class.window(request))
      end
    end

    def observe(process, streams)
      readers = forward_streams(*streams.values_at(:stdout, :stderr))
      monitor(process, *streams.values_at(:name, :label))
      readers.each(&:value)
      interrupted_status || self.class.child_status(process.value)
    end

    def forward_streams(stdout, stderr)
      [forward_stdout(stdout), Thread.new { IO.copy_stream(stderr, $stderr) }]
    end

    def forward_stdout(stream)
      Thread.new do
        stream.each_line do |line|
          @plan_lines << line if line.start_with?(ChunkPlan::PREFIX)
          @settings.fetch(:output).write(line)
        end
      end
    end

    def interrupted_status
      128 + Signal.list.fetch(@signal) if @signal
    end

    def monitor(process, name, label)
      reporter = Progress.new(@settings.merge(docker: @docker, name: name, label: label))
      wait_for_process(process, reporter)
      stop(process, name) if interrupted_status
    end

    def wait_for_process(process, reporter)
      reporter.report_if_due until process.join(0.05) || @signal
    end

    def stop(process, name)
      warn "[backfill] Received #{@signal}; stopping only owned container #{name}."
      @docker.stop(name)
      Process.kill('TERM', process.pid) if process.alive?
    rescue Errno::ESRCH
      nil
    end

    def finalize(name, status)
      return @docker.remove(name) if status.zero?

      report_failure(name, status)
      raise ChildFailure, status
    end

    def report_failure(name, status)
      warn "[backfill] Container failed (exit #{status}, OOMKilled=#{@docker.oom(name)}). Retained: #{name}"
      warn "[backfill] Inspect with: docker inspect #{name}; docker logs #{name}"
      warn '[backfill] Completed days persist; rerun the same command safely after resolving the failure.'
      warn '[backfill] Check Docker, the existing database service, image dependencies and Compose configuration.'
    end
  end
end
