# frozen_string_literal: true

# Runs only a pinned, explicitly queued preseason review.
class PublishPreseasonJob < ApplicationJob
  queue_as :default

  def perform(publication_id)
    Rails.logger.info("Publishing preseason review ##{publication_id} (job #{job_id})")
    PreseasonPublicationExecution.new(PreseasonPublication.find(publication_id)).call
  end
end
