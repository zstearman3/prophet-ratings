# frozen_string_literal: true

# A durable worker result; its signature authenticates the exact reviewed projection.
class DepartureValidation < ApplicationRecord
  belongs_to :departure_batch
  belongs_to :departure_acquisition
  belongs_to :departure_dataset_normalization, optional: true
  belongs_to :offseason_input_revision, optional: true
  has_many :proposals, class_name: 'DepartureProposal', dependent: :restrict_with_exception
  has_one :approval, class_name: 'DepartureApproval', dependent: :restrict_with_exception

  def record_publication_failure(message)
    with_lock { update!(status: 'publish_failed', error: message) unless status.in?(%w[published stale]) }
  end

  def progress_status
    return status unless status == 'ready'
    return 'stale' unless current?

    approval ? 'publish_queued' : 'ready'
  end

  def review_state
    return 'Validation stale' if status.in?(%w[ready published]) && !current?
    return Departures::BatchPage::LABELS.fetch(status, status.humanize) unless status == 'ready'

    approval ? 'Publication queued' : 'Validation ready'
  end

  def current?
    Departures::ValidationIntegrity.new(self).current?
  end
end
