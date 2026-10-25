# frozen_string_literal: true

require 'rails_helper'
require 'open3'

RSpec.describe GoodJob::Configuration do
  it 'boots development and production with external execution and bounded pools despite an async environment override' do
    probe = <<~RUBY
      config = GoodJob.configuration
      puts JSON.generate(mode: config.execution_mode, queues: config.queue_string, processes: config.subprocesses,
                         polling: config.poll_interval, shutdown: config.shutdown_timeout, cron: config.enable_cron,
                         db_pool: ActiveRecord::Base.connection_pool.size, schedule: Rails.application.config.good_job.cron)
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
      next unless environment == 'production'

      entry = value.fetch('schedule').values.find { |item| item['class'] == 'ScheduledGameSyncJob' }
      schedule = Fugit.parse(entry.fetch('cron'))
      times = next_occurrences(schedule, Time.utc(2026, 3, 8, 5))
      expect(times).to eq(%w[2026-03-08T06:00:00Z 2026-03-08T11:00:00Z 2026-03-08T17:00:00Z])
      times = next_occurrences(schedule, Time.utc(2026, 11, 1, 4))
      expect(times).to eq(%w[2026-11-01T05:00:00Z 2026-11-01T06:00:00Z 2026-11-01T12:00:00Z])
    end
  end

  def next_occurrences(schedule, cursor)
    Array.new(3) do
      cursor = schedule.next_time(cursor)
      cursor.to_t.utc.iso8601
    end
  end
end
