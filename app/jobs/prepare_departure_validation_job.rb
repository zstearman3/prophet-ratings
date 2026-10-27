# frozen_string_literal: true

# Authenticates complete evidence on the globally serialized heavy queue using a scalar operation ID.
class PrepareDepartureValidationJob < HeavyJob
  rescue_from GoodJob::InterruptError do |error|
    Departures::ValidationPreparation.new(DepartureValidation.find(arguments.first)).record_interruption(error)
  end

  def perform(id)
    @operation = DepartureValidation.find(id)
    Departures::ValidationPreparation.new(operation).call
  end

  private

  attr_reader :operation
end
