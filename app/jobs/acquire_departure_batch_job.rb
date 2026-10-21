# frozen_string_literal: true

# Duplicate delivery serializes one attempt; interrupted runs require an explicit successor.
class AcquireDepartureBatchJob < ApplicationJob
  def perform(attempt_id)
    @attempt = DepartureAcquisition.find(attempt_id)
    GoodJob::Job.advisory_lock_key("prophet-ratings:departure-attempt:#{attempt_id}") do
      Departures::BatchAcquisition.new(attempt).call
    end
  end

  private

  attr_reader :attempt
end
