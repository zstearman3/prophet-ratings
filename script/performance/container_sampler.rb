# frozen_string_literal: true

module OffseasonPerformance
  # Samples whole-container counters and retains terminal Docker state for each isolated phase.
  class ContainerSampler
    SERVICES = %w[web worker db].freeze
    PROBE = 'cat /sys/fs/cgroup/memory.current /sys/fs/cgroup/memory.peak /sys/fs/cgroup/cpu.stat; cat /proc/1/status'

    def initialize(run)
      @run = run
      @sampling = false
      @samples = []
    end

    def call
      thread = start
      yield
      finish(thread)
    ensure
      stop(thread)
    end

    def start
      @sampling = true
      Thread.new { sample_loop }
    end

    def sample_loop
      while @sampling
        @samples << measure_containers
        sleep 0.5
      end
    end

    def stop(thread)
      @sampling = false
      thread&.join
    end

    def finish(thread)
      stop(thread)
      @samples << measure_containers
    end

    def measure_containers
      SERVICES.to_h do |service|
        id = @run.compose('ps', '-a', '-q', service).strip
        sample = @run.command('docker', 'exec', id, 'sh', '-c', PROBE, allow_failure: true)
        [service, ContainerSampler.parse(sample, id, service)]
      end
    end

    def self.parse(sample, id, service)
      lines = sample.lines
      peak = integer(lines[1])
      { 'service' => service, 'container_id' => id, 'at' => Time.now.utc.iso8601(6),
        'current_bytes' => integer(lines[0]), 'peak_bytes' => peak, 'cpu_usec' => sample[/usage_usec (\d+)/, 1]&.to_i,
        'rss_bytes' => sample[/^VmRSS:\s+(\d+)/, 1]&.to_i&.*(1024),
        'peak_method' => peak ? 'cgroup_v2_since_container_boot' : 'sampled_only' }
    end

    def self.integer(value)
      Integer(value.to_s.strip, exception: false)
    end

    def windows(scenario, phase)
      SERVICES.map { |service| window(service, scenario, phase) }
    end

    def window(service, scenario, phase)
      values = @samples.map { |sample| sample.fetch(service) }
      id = values.last.fetch('container_id')
      state = JSON.parse(@run.command('docker', 'inspect', '--format', '{{json .State}}', id))
      { 'scenario' => scenario, 'phase' => phase, 'service' => service, 'samples' => values, 'state' => state, 'limits' => limits(id),
        'failures' => ContainerSampler.failures(service, values, state) }
    end

    def limits(id)
      config = JSON.parse(@run.command('docker', 'inspect', '--format', '{{json .HostConfig}}', id))
      config.slice('Memory', 'MemorySwap', 'NanoCpus', 'CpuQuota', 'CpuPeriod')
    end

    def self.failures(service, values, state)
      database = service == 'db'
      database ? [] : Budgets.container(values, state)
    end
  end
end
