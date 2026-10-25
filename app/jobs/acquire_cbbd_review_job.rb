# frozen_string_literal: true

# No credentials are serialized, and duplicate deliveries never renew a run budget.
class AcquireCbbdReviewJob < HeavyJob
  rescue_from GoodJob::InterruptError do
    id = arguments.first
    GoodJob::Job.advisory_lock_key("prophet-ratings:cbbd-review:#{id}") do
      record = CbbdReviewRun.find(id)
      record.with_lock do
        if record.status.in?(%w[queued running])
          record.update!(status: 'failed',
                         failure: 'Worker interrupted; start a new bounded run. Retained evidence and budget are unchanged.')
        end
      end
    end
  end

  def perform(run_id)
    GoodJob::Job.advisory_lock_key("prophet-ratings:cbbd-review:#{run_id}") do
      @run = CbbdReviewRun.find(run_id)
      Ingestion::Cbbd::ReviewAcquisition.new(run).call
    end
  end

  private

  attr_reader :run
end
