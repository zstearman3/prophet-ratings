# frozen_string_literal: true

require 'benchmark'

module StatisticsUtils
  module_function

  def average(values)
    return 0.0 if values.empty?

    values.sum.to_f / values.size
  end

  def stddev(values)
    return 0.0 if values.size < 2

    mean = average(values)
    sum_of_squares = values.sum { |v| (v - mean)**2 }
    Math.sqrt(sum_of_squares / (values.size - 1))
  end

  ##
  # Calculates the mean absolute error (MAE) of the given values.
  # Returns nil if the input is empty or nil.
  # @param [Array<Numeric>] values - The array of values to compute the MAE for.
  # @return [Float, nil] The mean absolute error, or nil if input is blank.
  def mae(values)
    return nil if values.blank?

    values.compact.sum(&:abs) / values.compact.size.to_f
  end

  ##
  # Approximates the cumulative distribution function (CDF) of the standard normal distribution at the given value.
  # @param [Numeric] value - The point at which to evaluate the CDF.
  # @return [Float] The probability that a standard normal variable is less than or equal to the given value.
  def normal_cdf(value)
    # Approximation of the standard normal CDF using the error function
    0.5 * (1 + Math.erf(value / Math.sqrt(2)))
  end

  ##
  # Solves a weighted least squares problem with optional ridge regularization by invoking an external Python script.
  # Raises an ArgumentError if the weights array length does not match the b_vector length.
  # Returns the parsed JSON result from the Python solver.
  # @param [Array<Array<Numeric>>] a_rows - The coefficient matrix as an array of rows.
  # @param [Array<Numeric>] b_vector - The target vector.
  # @param [Array<Numeric>, nil] weights - Optional weights for each observation; defaults to all ones if not provided.
  # @return [Array<Float>] The solution vector parsed from the Python solver's JSON output.
  def solve_least_squares_with_python(a_rows, b_vector, **options)
    require 'open3'
    require 'json'

    ridge_alpha = options.fetch(:ridge_alpha)
    weights = options.fetch(:weights, nil) || Array.new(b_vector.length, 1.0)

    unless weights.size == b_vector.size
      raise ArgumentError, "Weights size (#{weights.size}) does not match b_vector size (#{b_vector.size})"
    end

    input_data = {
      a: a_rows,
      b: b_vector,
      w: weights,
      ridge_alpha:
    }

    input_data[:diagnostics] = options.fetch(:diagnostics, false)
    output = nil
    time = Benchmark.realtime do
      output, error, status = Open3.capture3('python3', 'lib/python/adjusted_stat_solver.py', stdin_data: input_data.to_json)
      raise "Python solver failed (#{status.exitstatus || status.termsig}): #{error.strip}" unless status.success?

      Rails.logger.debug { "Solver STDERR: #{error}" } unless error.empty?
    end
    Rails.logger.info("Python solver completed in #{time.round(2)}s")
    validate_solver_output(JSON.parse(output), a_rows.first.size)
  end

  def validate_solver_output(values, columns)
    unless values.is_a?(Array) && values.size == columns && values.all? { |value| value.is_a?(Numeric) && value.finite? }
      raise ArgumentError, "Solver must return #{columns} finite coefficients"
    end

    values
  end
end
