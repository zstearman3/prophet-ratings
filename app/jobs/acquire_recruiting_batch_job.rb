# frozen_string_literal: true

# The advisory lock prevents duplicate jobs fetching the same batch concurrently.
class AcquireRecruitingBatchJob < HeavyJob
  rescue_from GoodJob::InterruptError do
    id = arguments.first
    GoodJob::Job.advisory_lock_key("prophet-ratings:recruiting-batch:#{id}") do
      record = RecruitingBatch.find(id)
      record.with_lock do
        if record.status.in?(%w[queued fetching])
          record.update!(status: 'failed',
                         failure_message: 'Worker interrupted; explicitly fetch a new batch.')
        end
      end
    end
  end

  def perform(batch_id)
    @batch = RecruitingBatch.find(batch_id)
    GoodJob::Job.advisory_lock_key("prophet-ratings:recruiting-batch:#{batch.id}") do
      Recruiting::BatchAcquisition.new(batch).call
    end
  end

  private

  attr_reader :batch
end
