# frozen_string_literal: true

# A retained full-evidence certificate and bounded proposal/report for one acquisition.
class DepartureValidation < ApplicationRecord
  belongs_to :departure_batch
  belongs_to :departure_acquisition
  belongs_to :departure_dataset_normalization, optional: true
  belongs_to :offseason_input_revision, optional: true
  has_many :proposals, class_name: 'DepartureProposal', dependent: :restrict_with_exception
  has_one :approval, class_name: 'DepartureApproval', dependent: :restrict_with_exception

  def record_publication_failure(message)
    with_lock { update!(status: 'publish_failed', error: message) unless status == 'published' }
  end

  def progress_status
    return status unless status == 'ready'
    return 'stale' unless current?

    approval ? 'publish_queued' : 'ready'
  end

  def review_state
    return 'Validation stale' if status.in?(%w[ready published]) && !current?
    return Departures::BatchPage::LABELS.fetch(status, status.humanize) unless status == 'ready'
    return 'Published inputs verified' if choices['historical_revision_id']

    approval ? 'Publication queued' : 'Validation ready'
  end

  def current?
    validator_version == Departures::ValidationPreparation::VERSION && (status == 'published' ? published_generation : generation) == Departures::ValidationPreparation.generation
  end
end
