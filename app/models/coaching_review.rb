# frozen_string_literal: true

# Readiness is an explicit operator decision, independent of Season preparation.
class CoachingReview < ApplicationRecord
  validates :discovery_status, inclusion: { in: %w[idle queued fetching complete failed] }
  validates :year, numericality: { only_integer: true, in: 1..9999 }, uniqueness: true
  validate :resolved_candidates
  validate :immutable_year, on: :update
  around_save :serialize_readiness

  def self.with_year_locks(years)
    years.compact.uniq.sort.each do |year|
      connection.execute(sanitize_sql_array(['SELECT pg_advisory_xact_lock(73127, ?)', Integer(year)]))
    end
    yield
  end

  def queue_discovery
    return if discovery_status.in?(%w[queued fetching])

    transaction do
      update!(discovery_status: 'queued', discovery_error: nil)
      enqueue_discovery
    end
  end

  private

  def enqueue_discovery
    return if DiscoverCoachingChangesJob.perform_later(id)

    raise ActiveJob::EnqueueError, 'The job was not enqueued.'
  rescue StandardError => error
    raise ArgumentError, "Coaching discovery could not be queued: #{error.message}"
  end

  def resolved_candidates
    return unless ready? && CoachingChange.exists?(effective_year: year, status: 'pending')

    errors.add(:ready, 'requires confirming or rejecting every pending coaching candidate for this year')
  end

  def immutable_year
    errors.add(:year, 'cannot change; create a review for the new year') if will_save_change_to_year?
  end

  def serialize_readiness
    self.class.with_year_locks([year]) do
      resolved_candidates
      raise ActiveRecord::RecordInvalid, self if errors.any?

      yield
    end
  end
end
