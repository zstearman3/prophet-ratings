# frozen_string_literal: true

# Complete evidence authentication runs on the existing globally serialized heavy queue.
class PrepareDepartureValidationJob < HeavyJob
  rescue_from GoodJob::InterruptError do |error|
    Departures::ValidationPreparation.new(DepartureValidation.find(arguments.first)).record_interruption(error)
  end

  def perform(operation_id)
    @operation = DepartureValidation.find(operation_id)
    Departures::ValidationPreparation.new(operation).call
  end

  private

  attr_reader :operation
end
