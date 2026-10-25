# frozen_string_literal: true

# Prevent duplicate discovery jobs from importing the same year concurrently.
class DiscoverCoachingChangesJob < HeavyJob
  rescue_from GoodJob::InterruptError do
    record = CoachingReview.find(arguments.first)
    GoodJob::Job.advisory_lock_key("prophet-ratings:coaching-discovery:#{record.year}") do
      record.with_lock do
        if record.discovery_status.in?(%w[queued fetching])
          record.update!(discovery_status: 'failed',
                         discovery_error: 'Worker interrupted; explicitly queue discovery again.')
        end
      end
    end
  end

  def perform(review_id)
    @review = CoachingReview.find(review_id)
    GoodJob::Job.advisory_lock_key("prophet-ratings:coaching-discovery:#{review.year}") do
      Coaching::Discovery.new(review).call
    end
  end

  private

  attr_reader :review
end
