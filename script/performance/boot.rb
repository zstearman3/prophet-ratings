# frozen_string_literal: true

raise 'Benchmark bootstrap requires an explicit owner' unless ENV['BENCHMARK_OWNER']&.match?(/\Aoffseason-[a-f0-9]+\z/)
raise 'Benchmark must run in production' unless ENV['RAILS_ENV'] == 'production'

require_relative '../../config/application'
require_relative 'telemetry'
require_relative 'phase_queue'
Rails.application.config.before_initialize do
  Rails.application.config.active_job.queue_name_prefix = OffseasonPerformance::PhaseQueue.prefix(
    ENV.fetch('BENCHMARK_OWNER'), ENV.fetch('BENCHMARK_PHASE', 'setup')
  )
  Rails.application.config.good_job.enable_cron = false
  Rails.application.config.good_job.execution_mode = :external
  Rails.application.config.good_job.preserve_job_records = true
  Rails.application.config.server_timing = false
  Rails.application.config.middleware.use OffseasonPerformance::Middleware
end
require_relative '../../config/environment'
require 'good_job/cli'
require_relative 'offline'
require_relative 'job_output'
require_relative 'fixture'
OffseasonPerformance::Fixture.guard!
OffseasonPerformance::Telemetry.install
Ingestion::Cbbd::HttpTransport.define_singleton_method(:call) { |uri, key| OffseasonPerformance::Offline.call(uri, key) }
if ENV['BENCHMARK_ROLE'] == 'worker'
  Thread.new do
    loop do
      File.write('/benchmark/worker-current.tmp', JSON.generate(OffseasonPerformance::Telemetry.memory))
      File.rename('/benchmark/worker-current.tmp', '/benchmark/worker-current.json')
      sleep 0.1
    end
  end
end
ActiveJob::Base.around_perform do |job, block|
  OffseasonPerformance::Telemetry.measure('job', job.job_id) do |metrics|
    metrics['job_class'] = job.class.name
    block.call
    metrics['output_bytes'] = OffseasonPerformance::JobOutput.bytes(job)
    metrics['output_definition'] = OffseasonPerformance::JobOutput.definition(job)
    metrics['terminal'] = 'performed'
  end
end

require_relative 'solver_job'

require_relative 'mixed_jobs'

require_relative 'departure_cbbd_content'
require_relative 'departure_sources'
require_relative 'departure_normalization'
