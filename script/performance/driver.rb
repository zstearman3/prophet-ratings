# frozen_string_literal: true

require_relative 'boot' if $PROGRAM_NAME == __FILE__
require_relative 'budgets'
require_relative 'client'
require_relative 'scenario'
require_relative 'measurements'
require_relative 'job_driver'
require 'benchmark'
require 'securerandom'
require 'socket'

module OffseasonPerformance
  # Runs complete cold/warm/serial/concurrent windows without restarting measured containers.
  class Driver
    def initialize(name, phase)
      fixture = JSON.parse(File.read('/benchmark/fixture.json'))
      @scenario = Scenario.new(name, phase, fixture)
      @clients = JSON.parse(File.read('/benchmark/sessions.json')).map { |session| Client.new(session) }
      @jobs = JobDriver.new(@scenario)
    end

    def run
      result = { 'scenario' => @scenario.name, 'phase' => @scenario.phase, 'samples' => [], 'failures' => [], 'warmups' => [] }
      execute(result)
    rescue StandardError => error
      Measurements.failure(result, error)
    end

    def execute(result)
      collect(result)
      check(result) unless @scenario.solver?
      result
    end

    def collect(result)
      result['cold'] = sample(@clients.first) if @scenario.get?
      @scenario.solver? ? Driver.solver(result) : collect_windows(result)
    end

    def self.solver(result)
      job = SolverJob.perform_later
      result['worker'] = JobDriver.wait_job(job.job_id)
      result['solution'] = JSON.parse(File.read('/benchmark/solver.json'))
    end

    def collect_windows(result)
      if @scenario.concurrent?
        result['warmups'] = concurrent_requests(10)
        result['samples'] = concurrent_requests(30)
      else
        serial_requests(result, 'warmups', 10)
        serial_requests(result, 'samples', 30)
      end
    end

    def serial_requests(result, key, count)
      client = @clients.first
      count.times { result.fetch(key) << sample(client) }
    end

    def check(result)
      Measurements.check(result, limit: @scenario.limit)
    end

    def concurrent_requests(count)
      queue = Driver.request_queue(count)
      threads = workers(queue)
      threads.flat_map(&:value).sort_by { |row| row.fetch('ordinal') }
    end

    def self.request_queue(count)
      Queue.new.tap { |queue| count.times { |index| queue << index } }
    end

    def workers(queue)
      @clients.map { |client| Thread.new { thread_requests(client, queue) } }
    end

    def thread_requests(client, queue)
      values = []
      while (index = self.class.pop(queue))
        values << sample(client).merge('ordinal' => index)
      end
      values
    end

    def self.pop(queue)
      queue.pop(true)
    rescue ThreadError
      nil
    end

    def sample(client)
      state = @jobs.prepare
      result = http_sample(client, state['publication'])
      @jobs.complete(result, state)
    end

    def http_sample(client, publication)
      id = SecureRandom.hex(12)
      response, elapsed = timed_request(client, publication, id)
      Measurements.http(response, id,
                        { 'elapsed' => elapsed, 'valid' => @scenario.valid_response?(response), 'scenario' => @scenario.name })
    end

    def timed_request(client, publication, id)
      method = @scenario.http_method
      response = nil
      elapsed = Benchmark.realtime do
        response = client.request(method, @scenario.path(publication), values: @scenario.form(publication), id:)
      end
      [response, elapsed]
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.first == 'auth'
    sessions = Array.new(3) { OffseasonPerformance::Client.new.authenticate }
    File.write('/benchmark/sessions.json', JSON.generate(sessions))
  else
    result = OffseasonPerformance::Driver.new(*ARGV).run
    File.write("/benchmark/#{ARGV.join('-')}.json", JSON.pretty_generate(result))
    exit(result['error'] ? 2 : 0)
  end
end
