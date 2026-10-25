# frozen_string_literal: true

module OffseasonPerformance
  # Retains the existing real-solver operands throughout the measured HTTP window.
  class MixedHeavyJob < HeavyJob
    def perform(token, season_id, model_id)
      MixedHeavyJob.verify_fixture(season_id, model_id)
      operands = MixedHeavyJob.solution
      ready = signal_ready(token)
      hold(token, ready)
      # Referencing operands after the hold keeps the representative live work reachable.
      write_result(MixedHeavyJob.dimensions(operands), operands.fetch(:error), ready)
    end

    def self.verify_fixture(season_id, model_id)
      Season.find(season_id)
      RatingsConfigVersion.find(model_id)
    end

    def self.solution
      matrix = SolverJob.matrix
      expected = MixedHeavyJob.expected
      actual = StatisticsUtils.solve_least_squares_with_python(matrix, expected * 2, ridge_alpha: 0)
      { matrix:, expected:, actual:, error: SolverJob.verify(actual, expected) }
    end

    def self.dimensions(operands)
      matrix = operands.fetch(:matrix)
      { rows: matrix.length, columns: matrix.first.length }
    end

    def self.expected
      Array.new(730) { |index| index.even? ? 2.0 : -3.0 }
    end

    def signal_ready(token)
      ready = Telemetry.now
      File.write("/benchmark/mixed-ready-#{token}.json", JSON.generate(job_id:, ready_at: Time.now.to_f))
      ready
    end

    def write_result(dimensions, error, ready)
      result = dimensions.merge(max_absolute_error: error, held_seconds: Telemetry.now - ready, process_pid: Process.pid)
                         .merge(MixedHeavyJob.runtime)
      File.write("/benchmark/mixed-#{job_id}.json", JSON.generate(result))
    end

    def self.runtime
      config = GoodJob.configuration
      { queues: config.queue_string, subprocesses: config.subprocesses,
        db_pool: ActiveRecord::Base.connection_pool.size, rails_max_threads: ENV.fetch('RAILS_MAX_THREADS') }
    end

    def hold(token, ready)
      loop do
        elapsed = Telemetry.now - ready
        return if elapsed >= 10 && File.exist?("/benchmark/mixed-release-#{token}")
        raise 'Mixed workload driver did not release held work' if elapsed > 120

        sleep 0.1
      end
    end
  end

  # Uses the ordinary pool and the same pinned fixture identities, without provider HTTP.
  class MixedOrdinaryJob < ApplicationJob
    queue_as :default

    def perform(token, season_id, model_id)
      Season.find(season_id)
      RatingsConfigVersion.find(model_id)
      sleep 0.05
      File.write("/benchmark/mixed-#{job_id}.json", JSON.generate(token:, season_id:, model_id:, process_pid: Process.pid))
    end
  end
end
