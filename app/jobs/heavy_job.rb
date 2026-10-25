# frozen_string_literal: true

# One shared lock also protects retained deliveries on the old default queue.
class HeavyJob < ApplicationJob
  LOCK_KEY = 'prophet-ratings:heavy-work'
  # Exhausted contention stays visible as a failed retained delivery.
  class Contention < StandardError; end

  queue_as :heavy
  around_perform :with_heavy_lock

  # Exhaustion must remain a failed job even when a child discards StandardError.
  def rescue_with_handler(error)
    raise error if error.is_a?(Contention)

    super
  end

  private

  def with_heavy_lock
    acquired = GoodJob::Job.advisory_lock_key(LOCK_KEY) do
      yield
      true
    end
    retry_heavy unless acquired
  end

  def retry_heavy
    raise Contention, 'Heavy worker busy after five deliveries; inspect GoodJob and explicitly retry.' if executions >= MAX_EXECUTIONS

    retry_job(wait: 5.seconds, queue: :heavy)
  end
end
