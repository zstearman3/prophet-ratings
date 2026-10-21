# frozen_string_literal: true

# No credentials are serialized, and duplicate deliveries never renew a run budget.
class AcquireCbbdReviewJob < ApplicationJob
  def perform(run_id)
    GoodJob::Job.advisory_lock_key("prophet-ratings:cbbd-review:#{run_id}") do
      @run = CbbdReviewRun.find(run_id)
      Ingestion::Cbbd::ReviewAcquisition.new(run).call
    end
  end

  private

  attr_reader :run
end
