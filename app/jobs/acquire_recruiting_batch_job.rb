# frozen_string_literal: true

# The advisory lock prevents duplicate jobs fetching the same batch concurrently.
class AcquireRecruitingBatchJob < ApplicationJob
  def perform(batch_id)
    @batch = RecruitingBatch.find(batch_id)
    GoodJob::Job.advisory_lock_key("prophet-ratings:recruiting-batch:#{batch.id}") do
      Recruiting::BatchAcquisition.new(batch).call
    end
  end

  private

  attr_reader :batch
end
