# frozen_string_literal: true

# Prevent duplicate discovery jobs from importing the same year concurrently.
class DiscoverCoachingChangesJob < ApplicationJob
  def perform(review_id)
    @review = CoachingReview.find(review_id)
    GoodJob::Job.advisory_lock_key("prophet-ratings:coaching-discovery:#{review.year}") do
      Coaching::Discovery.new(review).call
    end
  end

  private

  attr_reader :review
end
