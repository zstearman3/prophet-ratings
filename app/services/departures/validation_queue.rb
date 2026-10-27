# frozen_string_literal: true

module Departures
  # Only current-acquisition work is reused; explicit interrupted recovery excludes a live worker.
  class ValidationQueue
    def initialize(batch)
      @batch = batch
    end

    def call(close_interrupted: nil)
      operation = ValidationLocks.web_transaction { claim(close_interrupted) }
      self.class.enqueue(operation)
    end

    def self.enqueue(operation)
      PrepareDepartureValidationJob.perform_later(operation.id) if operation.previously_new_record?
      operation
    end

    private

    def claim(close_interrupted)
      DepartureBatch.select(:id).lock('FOR UPDATE NOWAIT').find(@batch.id)
      operation = active
      return operation if operation && !close_interrupted

      close(operation) if operation
      ValidationPreparation.create(@batch)
    end

    def active
      attempt_id = @batch.acquisitions.order(id: :desc).pick(:id)
      DepartureValidation.where(departure_batch_id: @batch.id, departure_acquisition_id: attempt_id,
                                status: %w[queued running]).order(:id).last
    end

    def close(operation)
      closed = ValidationPreparation.with_operation_lock(operation.id) { self.class.close_locked(operation) }
      Contract.check!(closed, 'Departure validation worker is busy; retry after it finishes')
    end

    public_class_method def self.close_locked(operation)
      operation.with_lock do
        Contract.check!(operation.certificate.blank?, 'Sealed departure evidence cannot be replaced; revalidate')
        operation.update!(status: 'failed', error: 'Operator confirmed interrupted validation; revalidate')
        true
      end
    end
  end
end
