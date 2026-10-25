# frozen_string_literal: true

# Runs only a pinned, explicitly queued preseason review.
class PublishPreseasonJob < HeavyJob
  rescue_from GoodJob::InterruptError do
    Season.with_ratings_lock do
      record = PreseasonPublication.find(arguments.first)
      record.with_lock do
        if record.status.in?(%w[queued running])
          record.update!(status: 'failed',
                         error_message: 'Worker interrupted; review the pinned proposal and retry if inputs are current.')
        end
      end
    end
  end

  def perform(publication_id)
    Rails.logger.info("Publishing preseason review ##{publication_id} (job #{job_id})")
    PreseasonPublicationExecution.new(PreseasonPublication.find(publication_id)).call
  end
end
