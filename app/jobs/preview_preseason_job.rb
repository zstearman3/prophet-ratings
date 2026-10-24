# frozen_string_literal: true

# Builds saved review evidence without occupying the HTTP request.
class PreviewPreseasonJob < ApplicationJob
  queue_as :default

  def perform(publication_id)
    Rails.logger.info("Previewing preseason review ##{publication_id} (job #{job_id})")
    PreseasonPublicationPreviewExecution.new(PreseasonPublication.find(publication_id)).call
  end
end
