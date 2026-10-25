# frozen_string_literal: true

# Only scalar stored identities cross the queue boundary; no replay in the HTTP process.
class CompareCbbdReviewJob < HeavyJob
  include GoodJob::ActiveJobExtensions::Labels

  self.good_job_labels = [-> { "cbbd-comparison:#{arguments.first}" }]

  def perform(run_id, identity)
    @run = CbbdReviewRun.find(run_id)
    Ingestion::Reconciliation::RunReview.new(run).compare_pinned(identity)
  end

  private

  attr_reader :run
end
