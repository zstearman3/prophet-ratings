# frozen_string_literal: true

# Authenticates complete evidence on the globally serialized heavy queue using a scalar operation ID.
class PrepareDepartureValidationJob < HeavyJob
  def perform(id)
    @operation = DepartureValidation.find(id)
    Departures::ValidationPreparation.new(operation).call
  end

  private

  attr_reader :operation
end
