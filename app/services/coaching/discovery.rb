# frozen_string_literal: true

module Coaching
  # Failed discovery retains existing decisions; successful imports keep their readiness rules.
  class Discovery
    def initialize(review)
      @review = review
    end

    def call
      return unless review.reload.discovery_status.in?(%w[queued fetching])

      acquire
    rescue StandardError => error
      record_failure(error)
    end

    private

    attr_reader :review

    def acquire
      review.update!(discovery_status: 'fetching')
      CoachingReview.transaction do
        CoachingChangesImport.new(year: review.year).call
        review.reload.update!(discovery_status: 'complete', discovered_at: Time.current, discovery_error: nil)
      end
    end

    def record_failure(error)
      message = error.message
      review.reload.update!(discovery_status: 'failed', discovery_error: message)
      Rails.logger.error("Coaching discovery #{review.year} failed: #{error.class}: #{message}")
    rescue StandardError
      raise error
    end
  end
end
