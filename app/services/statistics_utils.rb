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
end
