# frozen_string_literal: true

require_relative 'boot'
OffseasonPerformance::Fixture.new(scale: Integer(ENV.fetch('BENCHMARK_SCALE'))).call(phase: ARGV.fetch(0))
