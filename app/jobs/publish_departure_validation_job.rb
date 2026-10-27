# frozen_string_literal: true

# Publishes one immutable approval; exact repeated deliveries retain their original result.
class PublishDepartureValidationJob < HeavyJob
  rescue_from GoodJob::InterruptError do |error|
    DepartureApproval.find(arguments.first).departure_validation.record_publication_failure(error.message)
  end

  def perform(id)
    @approval = DepartureApproval.find(id)
    Departures::ValidationPublication.new(approval).call
  rescue StandardError => error
    approval&.departure_validation&.record_publication_failure(error.message)
    raise
  end

  private

  attr_reader :approval
end
