# frozen_string_literal: true

# Saved operator preparation and decisions, separate from immutable published evidence.
class DepartureBatch < ApplicationRecord
  belongs_to :season
  belongs_to :revision, class_name: 'OffseasonInputRevision', optional: true
  belongs_to :predecessor, class_name: 'DepartureBatch', optional: true
  has_many :acquisitions, class_name: 'DepartureAcquisition', dependent: :restrict_with_exception

  validates :status, inclusion: { in: %w[draft published] }

  def readonly?
    persisted? && status_in_database == 'published'
  end

  def latest_revision
    OffseasonInputRevision.where(season:, kind: 'departures').order(:id).last
  end

  def attempt
    acquisitions.order(:id).last
  end

  def require_editable
    raise ArgumentError, 'Published departure batches are closed; start a correction.' if status == 'published'
    raise ArgumentError, 'Wait for acquisition to finish before editing.' if attempt&.status.in?(%w[queued running])
  end
end
