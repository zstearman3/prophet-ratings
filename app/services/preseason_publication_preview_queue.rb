# frozen_string_literal: true

# Retries retain the originally selected model and selection generation.
class PreseasonPublicationPreviewQueue
  def initialize(publication)
    @publication = publication
  end

  def call
    enqueue if prepare
    PreseasonPublicationPage.summary(PreseasonPublication.all).find(publication.id)
  end

  private

  def prepare
    return unless publication.status.start_with?('preview_')

    publication.with_lock { record_queue }
  end

  def record_queue
    return unless publication.status.start_with?('preview_')

    publication.update!(status: 'preview_queued', error_message: nil)
  end

  attr_reader :publication

  def enqueue
    return if PreviewPreseasonJob.perform_later(publication.id)

    raise ActiveJob::EnqueueError, 'The preview job was not enqueued.'
  rescue StandardError => error
    publication.with_lock do
      if publication.status == 'preview_queued'
        publication.update!(status: 'preview_failed',
                            error_message: "Could not enqueue preview: #{error.message}. Retry after checking the worker.")
      end
    end
  end
end
