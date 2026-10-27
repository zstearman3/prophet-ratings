# frozen_string_literal: true

module Departures
  # Parse a coherent snapshot, then reauthenticate actual content under locks before signing.
  class ValidationPreparation
    VERSION = 'departure-validation-signed-v2'

    def self.create(batch)
      attempt = batch.acquisitions.select(:id, :status).order(:id).last
      Contract.check!(attempt&.terminal?, 'Acquire usable evidence before validation')
      DepartureValidation.create!(departure_batch: batch, departure_acquisition: attempt, validator_version: VERSION)
    end

    def self.queue(batch)
      operation = ValidationLocks.web_transaction { claim_batch(batch) }
      PrepareDepartureValidationJob.perform_later(operation.id) if operation.previously_new_record?
      operation
    end

    def self.claim_batch(batch)
      id = batch.id
      DepartureBatch.select(:id).lock('FOR UPDATE NOWAIT').find(id)
      active = DepartureValidation.where(departure_batch_id: id, status: %w[queued running]).order(:id).last
      active || create(batch)
    end

    def initialize(operation)
      @operation = operation
    end

    def call
      prepare if claim
      @operation
    rescue StandardError => error
      @operation.reload.update!(status: 'failed', error: error.message)
      @operation
    end

    private

    def claim
      @operation.with_lock do
        next false unless @operation.status == 'queued'

        @operation.update!(status: 'running', error: nil)
        true
      end
    end

    def prepare
      proof = snapshot
      @operation.reload
      DepartureValidation.transaction { ValidationLocks.lock { seal(proof) } }
    end

    def seal(proof)
      integrity = ValidationIntegrity.new(@operation)
      Contract.check!(proof == [integrity.dependency_hash, integrity.artifacts],
                      'Departure evidence changed during preparation; revalidate')
      @operation.update!(status: 'ready', dependency_hash: proof.first, artifacts: proof.last)
      @operation.update!(certificate: integrity.sign)
    end

    def snapshot
      DepartureValidation.transaction(isolation: :repeatable_read) do
        identity = ValidationIntegrity.new(@operation).dependency_hash
        prepare_projection
        [identity, ValidationArtifacts.new(@operation).call]
      end
    end

    def prepare_projection
      record = ValidationEvidence.new(@operation).call
      @operation.update!(departure_dataset_normalization_id: record.id)
      @operation.update!(**PreparedProposal.new(@operation, record).call)
    end
  end
end
