# frozen_string_literal: true

require 'rails_helper'
require 'open3'

RSpec.describe GoodJob::Configuration do
  it 'boots development and production with external execution and bounded pools despite an async environment override' do
    probe = <<~RUBY
      config = GoodJob.configuration
      puts JSON.generate(mode: config.execution_mode, queues: config.queue_string, processes: config.subprocesses,
                         polling: config.poll_interval, shutdown: config.shutdown_timeout, cron: config.enable_cron,
                         db_pool: ActiveRecord::Base.connection_pool.size)
    RUBY
    %w[development production].each do |environment|
      output, error, status = Open3.capture3({ 'RAILS_ENV' => environment, 'GOOD_JOB_EXECUTION_MODE' => 'async',
                                               'SECRET_KEY_BASE' => 'synthetic-test-secret', 'GOOD_JOB_ENABLE_CRON' => 'false' },
                                             RbConfig.ruby, '-r', './config/environment', '-e', probe)
      expect(status.success?).to be(true), error
      value = JSON.parse(output.lines.last)
      expect(value).to include('mode' => 'external', 'queues' => 'heavy:1;-heavy:1', 'processes' => 0,
                               'polling' => 1, 'shutdown' => 30, 'db_pool' => 6)
      expect(value.fetch('cron')).to be(false) if environment == 'development'
    end
  end
end
