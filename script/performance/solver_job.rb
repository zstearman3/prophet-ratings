# frozen_string_literal: true

module OffseasonPerformance
  # Exercises the real Python boundary with an independently known deterministic solution.
  class SolverJob < ApplicationJob
    def perform
      solution = self.class.solution.merge(job_id:)
      File.write('/benchmark/solver.json', JSON.generate(solution))
    end

    def self.solution
      expected = Array.new(730) { |index| index.even? ? 2.0 : -3.0 }
      actual = StatisticsUtils.solve_least_squares_with_python(matrix, expected * 2, ridge_alpha: 0)
      { rows: 1460, columns: 730, max_absolute_error: verify(actual, expected) }
    end

    def self.matrix
      Array.new(1460) do |index|
        row = Array.new(730, 0.0)
        row[index % 730] = 1.0
        row
      end
    end

    def self.verify(actual, expected)
      verify_shape(actual, expected.length)
      error = actual.zip(expected).map { |value, target| (value - target).abs }.max
      raise "Incorrect real solver result: #{error}" unless error <= 1e-8

      error
    end

    def self.verify_shape(actual, expected_size)
      correct_size = actual.is_a?(Array) && actual.length == expected_size
      raise 'Incorrect real solver coefficient count' unless correct_size

      verify_values(actual)
    end

    def self.verify_values(actual)
      valid = actual.all? { |value| value.is_a?(Numeric) && value.finite? }
      raise 'Invalid real solver coefficient' unless valid
    end
  end
end
