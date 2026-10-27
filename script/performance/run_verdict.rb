# frozen_string_literal: true

module OffseasonPerformance
  # Keeps operational/incomplete failures nonzero even when baseline mode allows measured budget breaches.
  module RunVerdict
    COVERAGE = { true => 'measured', false => 'incomplete' }.freeze
    def self.coverage(result, scenarios)
      coverage = {}
      scenarios.each { |scenario| coverage[scenario] = scenario_coverage(result.fetch('scenarios'), scenario) }
      coverage
    end

    def self.scenario_coverage(results, scenario)
      values = results.select { |entry| entry['scenario'] == scenario }
      expected = phase_count(scenario)
      complete = scenario_complete?(values, expected)
      if scenario == 'departure_validation'
        complete &&= values.map { |entry| entry.fetch('phase') }.sort == DepartureValidationDriver::PHASES.sort
      end
      COVERAGE.fetch(complete)
    end

    def self.phase_count(scenario)
      return DepartureValidationDriver::PHASES.length if scenario == 'departure_validation'

      get = Runner::GETS.include?(scenario) || %w[departure_normalization departure_validation].include?(scenario)
      get ? 2 : 1
    end

    def self.scenario_complete?(values, expected)
      correct_count = values.size == expected
      correct_count && values.none? { |entry| entry['error'] }
    end

    def self.complete?(result)
      result.fetch('errors').empty? && result.fetch('coverage').values.all?('measured')
    end

    def self.passed?(result)
      complete?(result) && result.fetch('scenarios').all? { |entry| entry.fetch('failures').empty? } &&
        result.fetch('container_windows').all? { |window| window.fetch('failures').empty? }
    end

    def self.operational_failure?(result)
      !complete?(result) || result.fetch('scenarios').any? { |value| value['error'] } ||
        result.fetch('container_windows').any? { |window| window.fetch('state')['OOMKilled'] } || measurement_missing?(result)
    end

    def self.exit_code(result, options)
      return 2 if operational_failure?(result)

      options[:assert] && !result.fetch('pass') ? 1 : 0
    end

    def self.measurement_missing?(result)
      entries = result.fetch('scenarios') + result.fetch('container_windows')
      failures = entries.flat_map { |entry| entry.fetch('failures') }
      failures.any? { |failure| failure.match?(/missing|invalid|expected 30|incomplete|exited unexpectedly/) }
    end
  end
end
