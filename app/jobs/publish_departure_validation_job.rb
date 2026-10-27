# frozen_string_literal: true

# Retries retain the immutable approval; failed transactions never leave partial revision/profile writes.
class PublishDepartureValidationJob < HeavyJob
  rescue_from GoodJob::InterruptError, with: :record_failure

  def perform(approval_id)
    @approval = DepartureApproval.find(approval_id)
    Departures::ValidationPublication.new(approval).call
  rescue StandardError => error
    record_failure(error)
  end

  private

  attr_reader :approval

  def record_failure(error)
    @approval ||= DepartureApproval.find(arguments.first)
    message = error.message
    persist_failure(message)
    Rails.logger.error("Departure publication failed: #{error.class}: #{message}")
  end

  def persist_failure(message)
    approval.departure_validation.record_publication_failure(message)
  end
end
