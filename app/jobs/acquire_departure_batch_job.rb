# frozen_string_literal: true

# Duplicate delivery serializes one attempt; interrupted runs require an explicit successor.
class AcquireDepartureBatchJob < HeavyJob
  rescue_from GoodJob::InterruptError do
    id = arguments.first
    GoodJob::Job.advisory_lock_key("prophet-ratings:departure-attempt:#{id}") do
      record = DepartureAcquisition.find(id)
      record.with_lock do
        if record.status.in?(%w[queued running])
          record.update!(status: 'failed',
                         failure: 'Worker interrupted; create a new bounded acquisition.', finished_at: Time.current)
        end
      end
    end
  end

  def perform(attempt_id)
    @attempt = DepartureAcquisition.find(attempt_id)
    GoodJob::Job.advisory_lock_key("prophet-ratings:departure-attempt:#{attempt_id}") do
      queue_validation if Departures::BatchAcquisition.new(attempt).call
    end
  end

  private

  attr_reader :attempt

  def queue_validation
    batch = DepartureBatch.select(:id, :status).find(attempt.departure_batch_id)
    latest = batch.acquisitions.order(id: :desc).pick(:id)
    return unless batch.status == 'draft' && latest == attempt.id && attempt.reload.terminal?

    Departures::ValidationPreparation.queue(batch)
  end
end
