# frozen_string_literal: true

# Builds saved review evidence without occupying the HTTP request.
class PreviewPreseasonJob < HeavyJob
  rescue_from GoodJob::InterruptError do
    Season.with_ratings_lock do
      record = PreseasonPublication.find(arguments.first)
      record.with_lock do
        if record.status.in?(%w[preview_queued preview_running])
          record.update!(status: 'preview_failed',
                         error_message: 'Worker interrupted; explicitly retry this preview or create a fresh preview if inputs changed.')
        end
      end
    end
  end

  def perform(publication_id)
    Rails.logger.info("Previewing preseason review ##{publication_id} (job #{job_id})")
    PreseasonPublicationPreviewExecution.new(PreseasonPublication.find(publication_id)).call
  end
end
