# frozen_string_literal: true

require 'json'

module OffseasonPerformance
  # Records scalar SQL/GC/memory measurements without retaining bind or notification payloads.
  module Telemetry
    def self.memory
      peak = counter('memory.peak')
      { 'current_bytes' => counter('memory.current'), 'peak_bytes' => peak, 'cpu_usec' => cpu_usec,
        'rss_bytes' => File.read('/proc/self/status')[/^VmRSS:\s+(\d+)/, 1].to_i * 1024,
        'peak_method' => peak ? 'cgroup_v2_since_container_boot' : 'sampled_only' }
    end

    def self.cgroup_value(name)
      path = File.join('/sys/fs/cgroup', name)
      File.read(path) if File.readable?(path)
    end

    def self.counter(name)
      value = cgroup_value(name)
      Integer(value) if value
    end

    def self.cpu_usec
      cgroup_value('cpu.stat')&.[](/usage_usec (\d+)/, 1)&.to_i
    end

    def self.now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def self.context
      Thread.current[:offseason_performance]
    end

    def self.context=(value)
      Thread.current[:offseason_performance] = value
    end

    def self.measure(kind, id)
      window = MetricWindow.new(kind, id)
      yield window.metrics
    ensure
      window&.finish
    end

    def self.write(metrics)
      File.open(ENV.fetch('BENCHMARK_TELEMETRY'), 'a') do |file|
        file.flock(File::LOCK_EX)
        file.puts(JSON.generate(metrics))
      end
    end

    def self.install
      ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, start, finish, _id, payload|
        metrics = context
        next unless metrics

        request_runtime(metrics)
        record_sql(metrics, payload, (finish - start) * 1000)
      end
    end

    def self.request_runtime(metrics)
      recorded = metrics.key?('query_cache_enabled')
      return if recorded

      metrics['query_cache_enabled'] = ActiveRecord::Base.connection.query_cache_enabled
    end

    def self.record_sql(metrics, payload, milliseconds)
      if payload[:cached]
        metrics['cache_hits'] += 1
      elsif payload[:name] != 'SCHEMA'
        metrics['sql_count'] += 1
        metrics['sql_ms'] += milliseconds
      end
    end
  end

  # Restores enclosing thread context and writes measurements even when the observed operation raises.
  class MetricWindow
    attr_reader :metrics

    def initialize(kind, id)
      @previous = Telemetry.context
      @metrics = { 'kind' => kind, 'id' => id, 'sql_count' => 0, 'sql_ms' => 0.0, 'cache_hits' => 0 }
      @started = Telemetry.now
      @gc = GC.stat
      Telemetry.context = @metrics
    end

    def finish
      @metrics.merge!(Telemetry.memory).merge!(deltas)
      Telemetry.write(@metrics)
    ensure
      Telemetry.context = @previous
    end

    def deltas
      { 'elapsed' => Telemetry.now - @started, 'gc_count_process_delta' => GC.stat(:count) - @gc[:count],
        'gc_ms_process_delta' => GC.stat(:time) - @gc[:time] }
    end
  end

  # Measures complete Rack response generation, including streamed body bytes.
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      Telemetry.measure('request', env['HTTP_X_BENCHMARK_ID'] || 'setup') do |metrics|
        self.class.response(metrics, @app.call(env))
      end
    end

    def self.response(metrics, response)
      status, headers, body = response
      chunks = consume(body)
      metrics['status'] = status
      metrics['output_bytes'] = chunks.sum(&:bytesize)
      [status, headers, chunks]
    end

    def self.consume(body)
      body.to_enum(:each).to_a
    ensure
      Rack::BodyProxy.new(body) { nil }.close
    end
  end
end
