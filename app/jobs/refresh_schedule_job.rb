# frozen_string_literal: true

# ID-only delivery; the lock spans acquisition and all date commits.
class RefreshScheduleJob < ApplicationJob
  discard_on StandardError
  rescue_from GoodJob::InterruptError do
    recover_interruption(arguments.first)
  end

  def perform(run_id)
    with_run_lock(run_id) { Ingestion::ScheduleRefreshExecution.new(run).call }
  end

  private

  attr_reader :run

  def with_run_lock(run_id)
    GoodJob::Job.advisory_lock_key("prophet-ratings:schedule-refresh:#{run_id}") do
      @run = ScheduleRefreshRun.find(run_id)
      yield
    end
  end

  def recover_interruption(run_id)
    with_run_lock(run_id) do
      case run.status
      when 'running'
        run.finish('incomplete', 'Worker interrupted. Explicitly retry unfinished dates with a new budget.')
      when 'queued'
        run.finish('failed', 'Worker interrupted before acquisition. Explicitly retry the requested dates.')
      end
    end
  end
end
