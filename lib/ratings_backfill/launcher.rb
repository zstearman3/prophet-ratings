# frozen_string_literal: true

require 'tempfile'
require_relative 'options'
require_relative 'chunk_plan'
require_relative 'container_runner'

module RatingsBackfill
  # Coordinates backend planning and bounded runs; snapshots remain the resume authority.
  class Launcher
    def initialize(arguments)
      @arguments = arguments
      @override = nil
      @runner = nil
      @output = $stdout
    end

    def call
      perform
    rescue ContainerRunner::ChildFailure => error
      error.status
    rescue OptionParser::ParseError, ArgumentError, KeyError, JSON::ParserError, Errno::ENOENT => error
      report_error(error)
    ensure
      @override&.close!
    end

    private

    def perform
      @output.sync = true
      options = Options.new(@arguments)
      return show_help(options) if options.values[:help]

      launch(options)
    end

    def report_error(error)
      warn "[backfill] #{error.message}"
      warn '[backfill] Check arguments, Docker availability, and local dependencies; use --help for usage.'
      1
    end

    def show_help(options)
      @output.write(options.help)
      0
    end

    def launch(options)
      DockerClient.new.verify
      configure_runner(options.values)
      with_signals { run_chunks(options) }
    end

    def configure_runner(settings)
      project, days, memory = settings.values_at(:project, :chunk_days, :memory)
      @output.write("[backfill] Compose project=#{project} chunk_days=#{days} memory=#{memory || 'inherited web cap'}\n")
      @runner = ContainerRunner.new(settings.merge(root: File.expand_path('../..', __dir__), output: @output,
                                                   compose_flags: compose_flags(settings)))
    end

    def compose_flags(settings)
      memory = settings[:memory]
      return [] unless memory

      prepare_override(memory)
      ['-f', @override.path]
    end

    def prepare_override(memory)
      @override = Tempfile.new(['prophet-backfill-', '.yml'])
      @override.write("services:\n  web:\n    mem_limit: #{memory}\n")
      @override.flush
    end

    def with_signals
      handlers = {}
      %w[INT TERM].each { |signal| handlers[signal] = trap_signal(signal) }
      yield
    ensure
      handlers&.each { |signal, handler| Signal.trap(signal, handler) }
    end

    def trap_signal(signal)
      Signal.trap(signal) { @runner.signal(signal) }
    end

    def run_chunks(options)
      plan = build_plan(options.request)
      return already_complete if plan.complete?

      execute_plan(plan, options.values.fetch(:chunk_days))
      0
    end

    def build_plan(request)
      @runner.run(request)
      plan = ChunkPlan.new(@runner.plan_lines)
      @output.write("[backfill] #{plan.summary}\n")
      plan
    end

    def already_complete
      @output.write("[backfill] Requested range already complete.\n")
      0
    end

    def execute_plan(plan, chunk_days)
      plan.each_request(chunk_days) { |request| @runner.run(request) }
      @output.write("[backfill] Backfill complete.\n")
    end
  end
end
