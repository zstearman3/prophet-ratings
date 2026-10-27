# frozen_string_literal: true

# Retains a single admin-requested operation and its eventual result.
class OffseasonReadinessOperation < ApplicationRecord
  belongs_to :season
  belongs_to :actor, class_name: 'User'
  belongs_to :offseason_readiness_review, optional: true

  validates :action, inclusion: { in: %w[report review season model] }
  validates :status, inclusion: { in: %w[queued running completed failed] }

  def enqueue
    raise 'Job was not accepted' unless ReadinessOperationJob.perform_later(id)
  rescue StandardError => error
    reload
    if status == 'queued'
      with_lock do
        update!(status: 'failed', error_message: "Could not enqueue: #{error.message}") if status == 'queued'
      end
    end
  end
end
