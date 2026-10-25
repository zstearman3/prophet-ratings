# frozen_string_literal: true

require 'benchmark'

module OffseasonPerformance
  # Boots one exact queue/HTTP phase and collects its request and whole-container evidence.
  class PhaseRunner
    def initialize(run, result, labels)
      @run = run
      @result = result
      @scenario = labels.fetch(:scenario)
      @phase = labels.fetch(:phase)
    end

    def call
      puts "#{@run.owner}: #{@scenario} #{@phase}"
      @result['scenarios'] << measure_phase
      File.write(@run.output, JSON.pretty_generate(@result))
      @run.compose('logs', '--no-color', 'web', 'worker', 'db')
    end

    def measure_phase
      boot = restart
      collect
      read_result.merge('scenario' => @scenario, 'phase' => @phase, 'boot_seconds' => boot)
    end

    def collect
      sampler = ContainerSampler.new(@run)
      sampler.call do
        @run.compose('run', '--rm', '--no-deps', '-T', 'driver', 'bundle', 'exec', 'ruby',
                     'script/performance/driver.rb', @scenario, @phase, allow_failure: true)
      end
      @result['container_windows'].concat(sampler.windows(@scenario, @phase))
    end

    def restart
      @run.env['BENCHMARK_PHASE'] = "#{@scenario}-#{@phase}"
      @run.compose('rm', '-s', '-f', 'web', 'worker')
      FileUtils.rm_f(File.join(@run.directory, 'worker-current.json'))
      Benchmark.realtime { boot }
    end

    def boot
      @run.compose('up', '-d', 'web', 'worker')
      @run.ready
      wait_worker_sampler
    end

    def wait_worker_sampler
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
      until File.exist?(File.join(@run.directory, 'worker-current.json'))
        self.class.check_deadline(deadline)
        sleep 0.1
      end
    end

    def self.check_deadline(deadline)
      expired = Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      raise 'Worker did not boot its memory sampler' if expired
    end

    def read_result
      path = File.join(@run.directory, "#{@scenario}-#{@phase}.json")
      return JSON.parse(File.read(path)) if File.exist?(path)

      { 'error' => 'Driver exited without result', 'failures' => ['missing result'] }
    end
  end
end
