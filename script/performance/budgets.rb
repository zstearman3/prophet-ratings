# frozen_string_literal: true

module OffseasonPerformance
  # Applies ticket limits to complete request windows and child-inclusive container counters.
  module Budgets
    MIB = 1024 * 1024

    def self.percentile(values, fraction = 0.95)
      return if values.empty?

      values.sort.fetch((values.length * fraction).ceil - 1)
    end

    def self.median(values)
      sorted = values.sort
      size = sorted.size
      return if size.zero?

      (sorted[(size - 1) / 2] + sorted[size / 2]) / 2.0
    end

    def self.window(samples, limit:)
      failures = completeness(samples)
      return failures unless failures.empty?

      performance_checks(samples, limit:)
    end

    def self.performance_checks(samples, limit:)
      latency = percentile(samples.map { |sample| sample.fetch('elapsed') }) > limit
      drift = memory_drift(samples) > 20 * MIB
      [("p95 exceeds #{limit}s" if latency), ('memory median drift exceeds 20 MiB' if drift)].compact
    end

    def self.completeness(samples)
      failures = []
      failures << 'expected 30 samples' unless samples.size == 30
      failures << 'invalid HTTP, missing telemetry or memory' unless samples.all? { |sample| valid_sample?(sample) }
      failures
    end

    def self.valid_sample?(sample)
      sample['valid'] && sample['telemetry'] && sample['current_bytes'].is_a?(Numeric) && sample['elapsed'].is_a?(Numeric)
    end

    def self.memory_drift(samples)
      current = samples.map { |sample| sample.fetch('current_bytes') }
      (median(current.last(10)) - median(current.first(10))).abs
    end

    def self.container(samples, state)
      failures = container_state(state)
      failures << 'missing container measurements' if samples.empty?
      failures << 'missing current counters' unless samples.all? { |sample| sample['current_bytes'].is_a?(Numeric) }
      failures.concat(peak_checks(samples))
    end

    def self.container_state(state)
      failures = []
      failures << 'OOMKilled' if state['OOMKilled']
      failures << 'container exited unexpectedly' if state['Running'] == false
      failures
    end

    def self.peak_checks(samples)
      peaks = samples.filter_map { |sample| sample['peak_bytes'] || sample['current_bytes'] }
      return ['missing peak/current counters'] if peaks.empty?
      return ['peak exceeds 400 MiB'] if peaks.max > 400 * MIB

      []
    end
  end
end
