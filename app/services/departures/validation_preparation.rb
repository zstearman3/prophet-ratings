# frozen_string_literal: true

module Departures
  # Parse a coherent snapshot, then reauthenticate its exact projection and actual content before signing.
  class ValidationPreparation
    VERSION = 'departure-validation-signed-v2'

    def self.create(batch)
      attempt = batch.acquisitions.select(:id, :status).order(:id).last
      Contract.check!(attempt&.terminal?, 'Acquire usable evidence before validation')
      DepartureValidation.create!(departure_batch: batch, departure_acquisition: attempt, validator_version: VERSION)
    end

    def self.queue(batch, close_interrupted: nil)
      ValidationQueue.new(batch).call(close_interrupted:)
    end

    def self.with_operation_lock(id, &)
      GoodJob::Job.advisory_lock_key("prophet-ratings:departure-validation:#{Integer(id)}", &)
    end

    def initialize(operation)
      @operation = operation
      @retention = ValidationDatasetRetention.new(operation)
    end

    def call
      self.class.with_operation_lock(@operation.id) { execute } || @operation
    end

    def record_interruption(error)
      @operation.with_lock do
        if @operation.certificate.blank? && @operation.status.in?(%w[queued running])
          @operation.update!(status: 'failed', error: "Worker interrupted; revalidate: #{error.message}")
        end
      end
    end

    private

    def execute
      prepare if claim
      @operation
    rescue StandardError => error
      record_failure(error)
    end

    def record_failure(error)
      raise error if error.is_a?(GoodJob::InterruptError)

      @operation.reload.update!(status: 'failed', error: error.message)
      @operation
    end

    def claim
      @operation.with_lock do
        next false unless @operation.status.in?(%w[queued running]) && @operation.certificate.blank?

        @operation.update!(status: 'running', error: nil)
        true
      end
    end

    def prepare
      @retention.prepare
      proof = snapshot
      DepartureValidation.transaction { ValidationLocks.lock { seal(proof) } }
    end

    def seal(proof)
      @operation.reload
      integrity = ValidationIntegrity.new(@operation)
      self.class.validate_proof(proof, integrity)
      @retention.call
      @operation.update!(status: 'ready', certificate: integrity.sign)
    end

    public_class_method def self.validate_proof(proof, integrity)
      valid = proof == integrity.seal && proof.fetch('dependency_hash') == integrity.dependency_hash &&
              proof.fetch('artifacts') == integrity.artifacts
      Contract.check!(valid, 'Departure evidence or proposals changed during preparation; revalidate')
    end

    def snapshot
      DepartureValidation.transaction(isolation: :repeatable_read) do
        identity = ValidationIntegrity.new(@operation).dependency_hash
        prepare_projection
        @operation.update!(dependency_hash: identity, artifacts: ValidationArtifacts.new(@operation).call)
        ValidationIntegrity.new(@operation).seal
      end
    end

    def prepare_projection
      record = ValidationEvidence.new(@operation).call
      DepartureProposal.where(departure_validation_id: @operation.id).delete_all
      @operation.update!(departure_dataset_normalization_id: record.id)
      @operation.update!(**PreparedProposal.new(@operation, record).call)
    end
  end
end
