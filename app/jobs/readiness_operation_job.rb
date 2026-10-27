# frozen_string_literal: true

# All expensive report and activation work runs away from web requests.
class ReadinessOperationJob < HeavyJob
  rescue_from GoodJob::InterruptError do
    operation = OffseasonReadinessOperation.find(arguments.first)
    unless operation.status == 'completed'
      operation.update!(status: 'failed',
                        error_message: 'Worker interrupted. Retry after the worker has stopped.')
    end
  end

  def perform(operation_id)
    GoodJob::Job.advisory_lock_key("prophet-ratings:readiness-operation:#{operation_id}") do
      operation = OffseasonReadinessOperation.find(operation_id)
      next unless operation.status.in?(%w[queued running])

      operation.update!(status: 'running', error_message: nil)
      execute(operation)
    end
  end

  private

  def execute(operation)
    return activate(operation) if operation.action.in?(%w[season model])

    operation.with_lock do
      return if operation.status == 'completed'

      case operation.action
      when 'report'
        operation.report = OffseasonReadiness.new(operation.season).call
      when 'review'
        operation.offseason_readiness_review = OffseasonReadinessReview.record!(operation.season, reviewer: operation.actor,
                                                                                                  **operation.inputs.symbolize_keys)
      end
      operation.update!(status: 'completed')
    end
  rescue StandardError => error
    operation.reload.update!(status: 'failed', error_message: "#{error.class}: #{error.message}".truncate(2000))
  end

  def activate(operation)
    OffseasonReadinessActivation.new(operation.offseason_readiness_review, actor: operation.actor, action: operation.action).call
    operation.update!(status: 'completed')
  end
end
