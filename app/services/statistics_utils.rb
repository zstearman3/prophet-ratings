module StatisticsUtils
  module_function

  def average(values)
    return 0.0 if values.empty?
    values.sum.to_f / values.size
  end

  def stddev(values)
    return 0.0 if values.size < 2
    mean = average(values)
    sum_of_squares = values.map { |v| (v - mean)**2 }.sum
    Math.sqrt(sum_of_squares / (values.size - 1))
  end

  def mae(values)
    return nil if values.blank?
    values.compact.map(&:abs).sum / values.compact.size.to_f
  end

  def normal_cdf(x)
    # Approximation of the standard normal CDF using the error function
    0.5 * (1 + Math.erf(x / Math.sqrt(2)))
  end
  
  def solve_least_squares_with_python(a_rows, b_vector, weights = nil)
    require 'open3'
    require 'json'
  
    ridge_alpha = Rails.application.config_for(:ratings).dig("ridge", "alpha") || 0.0
    weights ||= Array.new(b_vector.length, 1.0)
  
    unless weights.size == b_vector.size
      raise ArgumentError, "Weights size (#{weights.size}) does not match b_vector size (#{b_vector.size})"
    end
  
    input_data = {
      a: a_rows,
      b: b_vector,
      w: weights,
      ridge_alpha: ridge_alpha,
    }
  
    output = ''
    stderr_output = ''
    time = Benchmark.realtime do
      Open3.popen3("python3 lib/python/adjusted_stat_solver.py") do |stdin, stdout, stderr, wait_thr|
        stdin.puts input_data.to_json
        stdin.close
        output = stdout.read
        stderr_output = stderr.read
      end
    end
  
    Rails.logger.info("Python solver completed in #{time.round(2)}s")
    Rails.logger.debug("Solver STDOUT: #{output}")
    Rails.logger.debug("Solver STDERR: #{stderr_output}") unless stderr_output.empty?
  
    begin
      JSON.parse(output)
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse JSON output from solver.")
      Rails.logger.error("STDOUT: #{output.inspect}")
      Rails.logger.error("STDERR: #{stderr_output.inspect}")
      raise "JSON::ParserError in Python solver: #{e.message}"
    end
  end
end
