# frozen_string_literal: true

# Publishes one immutable approval; exact repeated deliveries retain their original result.
class PublishDepartureValidationJob < HeavyJob
  def perform(id)
    @approval = DepartureApproval.find(id)
    Departures::ValidationPublication.new(approval).call
  end

  private

  attr_reader :approval
end
