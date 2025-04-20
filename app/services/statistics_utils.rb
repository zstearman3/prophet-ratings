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

  def normal_cdf(x)
    # Approximation of the standard normal CDF using the error function
    0.5 * (1 + Math.erf(x / Math.sqrt(2)))
  end

  def solve_least_squares_with_python(a_rows, b_vector)
    require 'open3'
    require 'json'
  
    input_data = {
      a: a_rows,
      b: b_vector
    }
  
    time = Benchmark.realtime do
      @x_solution = nil
  
      Open3.popen3("python3 lib/python/adjusted_stat_solver.py") do |stdin, stdout, stderr, wait_thr|
        stdin.puts input_data.to_json
        stdin.close
        output = stdout.read
        @x_solution = JSON.parse(output)
      end
    end
  
    Rails.logger.info("Python solver completed in #{time.round(2)}s")
  
    @x_solution
  end  
end
