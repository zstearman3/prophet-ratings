# frozen_string_literal: true

module OffseasonPerformance
  # Summarizes complete windows while retaining raw request, worker and failure evidence.
  module Measurements
    def self.check(result, limit:)
      result['failures'].concat(failures(result, limit:))
      result['summary'] = summary(result.fetch('samples'))
    end

    def self.failures(result, limit:)
      samples = result.fetch('samples')
      Budgets.window(samples, limit:) + worker_stability(samples) + warmup_failures(result.fetch('warmups')) + cold_failures(result)
    end

    def self.warmup_failures(warmups)
      warmups.all? { |entry| entry['valid'] && entry['telemetry'] } ? [] : ['invalid warmup']
    end

    def self.cold_failures(result)
      return [] unless Scenario::GETS.include?(result.fetch('scenario'))

      cold = result['cold']
      return ['invalid or missing cold GET measurements'] unless valid_cold?(cold)

      cold['elapsed'] > 3 ? ['cold GET exceeds 3s'] : []
    end

    def self.valid_cold?(cold)
      return false unless cold.is_a?(Hash) && cold['valid'] == true

      valid_telemetry?(cold['telemetry']) && finite_nonnegative?(cold['elapsed']) && finite_nonnegative?(cold['current_bytes'])
    end

    def self.valid_telemetry?(telemetry)
      telemetry.is_a?(Hash) && !telemetry.empty?
    end

    def self.finite_nonnegative?(value)
      value.is_a?(Numeric) && value.real? && value.finite? && value >= 0
    end

    def self.summary(samples)
      return if samples.empty?

      current = samples.map { |entry| entry.fetch('current_bytes') }
      { 'p95_seconds' => Budgets.percentile(values(samples, 'elapsed')),
        'web_memory_drift_bytes' => Budgets.memory_drift(samples),
        'first_ten_median_bytes' => Budgets.median(current.first(10)), 'last_ten_median_bytes' => Budgets.median(current.last(10)) }
    end

    def self.values(samples, key)
      samples.map { |entry| entry.fetch(key) }
    end

    def self.worker_stability(samples)
      values = samples.map { |sample| sample.dig('worker_current', 'current_bytes') }
      return ['missing worker stability samples'] unless values.size == 30 && values.all?(Numeric)
      return [] if (Budgets.median(values.last(10)) - Budgets.median(values.first(10))).abs <= 20 * Budgets::MIB

      ['worker memory median drift exceeds 20 MiB']
    end

    def self.failure(result, error)
      result['error'] = "#{error.class}: #{error.message}"
      result['failures'] << 'incomplete scenario'
      result
    end

    def self.journal(kind, id)
      identity = { 'kind' => kind, 'id' => id }
      File.foreach('/benchmark/telemetry.jsonl').filter_map do |line|
        row = JSON.parse(line)
        row if row.slice('kind', 'id') == identity
      end.last
    end

    def self.http(response, id, options)
      value = { 'status' => response.code.to_i, 'body' => response.body }
      telemetry = journal('request', id)
      result = response_metrics(value, telemetry).merge(options.slice('elapsed', 'valid'), 'id' => id)
      verify_response(value, options)
      result
    end

    def self.response_metrics(value, telemetry)
      { 'worker_current' => worker_current, 'status' => value['status'],
        'output_bytes' => value.fetch('body').bytesize, 'telemetry' => telemetry, 'current_bytes' => telemetry&.fetch('current_bytes') }
    end

    def self.worker_current(retries = 4)
      JSON.parse(File.read('/benchmark/worker-current.json')).merge('sampler_read_retries' => 4 - retries)
    rescue Errno::ENOENT
      raise if retries.zero?

      sleep 0.05
      worker_current(retries - 1)
    end

    def self.verify_response(value, options)
      return if options.fetch('valid')

      raise "Unexpected HTTP #{options.fetch('scenario')}: #{value['status']}, #{value.fetch('body')[0, 250]}"
    end
  end
end
