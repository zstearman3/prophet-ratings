# frozen_string_literal: true

module Ingestion
  # Pin one finite acquisition and queue insertion atomically for explicit admin recovery.
  class GameIssueRetry
    def initialize(issue:, user:, fingerprint:)
      @issue = issue
      @user = user
      @fingerprint = fingerprint
    end

    def enqueue
      raise ArgumentError, 'Admin approval required.' unless @user&.admin?

      @issue.with_lock { enqueue_locked }
    end

    private

    def enqueue_locked
      raise ArgumentError, 'Source or game changed; reload before retrying.' unless @fingerprint == @issue.comparison_fingerprint
      return @issue.retry_job_id if %w[queued running].include?(@issue.retry_status)

      queue_retry
    end

    def queue_retry
      job = RetryGameIngestionIssueJob.new(@issue.id, acquisition.id)
      @issue.update!(retry_job_id: job.job_id, retry_status: 'queued')
      raise ActiveJob::EnqueueError, 'Issue retry could not be queued.' unless job.enqueue

      @issue.retry_job_id
    end

    def acquisition
      date = @issue.schedule_date
      acquisition = CbbdReviewRun.create!(season: @issue.season, start_date: date, end_date: date,
                                          maximum_requests: Integer(ENV.fetch('CBBD_SCHEDULED_MAX_REQUESTS', '50'), 10),
                                          retries: Integer(ENV.fetch('CBBD_SCHEDULED_RETRIES', '2'), 10))
      @issue.update!(retry_acquisition: acquisition)
      acquisition
    end
  end
end
