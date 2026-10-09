# frozen_string_literal: true

require_relative '../config/environment'

# Minimize (x-10)^2 + 4*(y-20)^2 + alpha*(x^2+y^2):
# x=10/(1+alpha), y=80/(4+alpha). Synthetic inputs only; no database calls.
[[0, [10.0, 20.0]], [4, [2.0, 10.0]]].each do |alpha, expected|
  actual = StatisticsUtils.solve_least_squares_with_python([[1, 0], [0, 1]], [10, 20], weights: [1, 4], ridge_alpha: alpha)
  raise "Incorrect solver result for ridge=#{alpha}: #{actual.inspect}" unless actual.zip(expected).all? do |value, target|
    (value - target).abs < 1e-10
  end

  puts "Verified ridge=#{alpha}: #{actual.inspect}"
end
