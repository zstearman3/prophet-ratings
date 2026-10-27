# frozen_string_literal: true

module Departures
  # A pre-read identity and final shared lock prevent mixed evidence from becoming a ready certificate.
  class ValidationPreparation
    VERSION = 'departure-validation-v1'
    # A prepared record and its compact proposal are sealed as a single unit.
    Prepared = Data.define(:record, :projection)

    def self.queue(batch)
      operation = claim_batch(batch)
      enqueue(operation) if operation.previous_changes.key?('id')
      operation
    rescue ActiveRecord::LockWaitTimeout
      raise ArgumentError, 'Departure publication is busy; retry shortly'
    end

    def self.claim_batch(batch)
      DepartureBatch.transaction do
        DepartureBatch.select(:id).lock('FOR UPDATE NOWAIT').find(batch.id)
        active(batch) || create(batch)
      end
    end

    def self.create(batch)
      attempt = batch.acquisitions.select(:id, :status).order(:id).last
      Contract.check!(attempt&.terminal?, 'Acquire usable evidence before validation')
      DepartureValidation.create!(departure_batch: batch, departure_acquisition: attempt, validator_version: VERSION)
    end

    def self.active(batch)
      DepartureValidation.where(departure_batch_id: batch.id, status: %w[queued running]).order(:id).last
    end

    def self.enqueue(operation)
      PrepareDepartureValidationJob.perform_later(operation.id)
      operation
    end

    def self.generation
      ApplicationRecord.uncached do
        ApplicationRecord.connection.select_value('SELECT generation FROM departure_dependency_generations WHERE id = 1').to_i
      end
    end

    def self.lock_generation
      ApplicationRecord.connection.select_value('SELECT generation FROM departure_dependency_generations WHERE id = 1 FOR UPDATE').to_i
    end

    def self.lock_generation_nowait
      ApplicationRecord.connection.select_value(
        'SELECT generation FROM departure_dependency_generations WHERE id = 1 FOR UPDATE NOWAIT'
      ).to_i
    rescue ActiveRecord::LockWaitTimeout
      raise ArgumentError, 'Departure publication is busy; retry shortly'
    end

    def initialize(operation)
      @operation = operation
      @identity = nil
    end

    def call
      return unless claim

      prepare
    rescue StandardError => error
      record_failure(error)
    end

    def record_failure(error)
      @operation.with_lock do
        @operation.update!(status: 'failed', error: error.message) if @operation.status == 'running'
      end
    end

    def record_interruption(error)
      @operation.with_lock do
        if @operation.generation.blank? && @operation.status.in?(%w[queued running])
          @operation.update!(status: 'failed', error: "Worker interrupted; revalidate: #{error.message}")
        end
      end
    end

    private

    def claim
      @operation.with_lock do
        return false unless @operation.status == 'queued'

        @operation.update!(status: 'running')
        true
      end
    end

    def prepare
      @identity = self.class.generation
      record = ValidationEvidence.new(@operation).call
      @operation.update!(departure_dataset_normalization_id: record.id)
      seal(Prepared.new(record:, projection: projection(record)))
    end

    def projection(record)
      HistoricalValidation.new(@operation).call(PreparedProposal.new(@operation, record).call)
    end

    def seal(prepared)
      DepartureValidation.transaction do
        self.class.lock_generation
        @operation.with_lock do
          return unless @operation.status == 'running'

          finalize(prepared)
        end
      end
    end

    def finalize(prepared)
      current = self.class.generation
      return stale unless @identity == current

      ready(prepared, retain_pending_dataset(prepared.record))
    end

    def retain_pending_dataset(record)
      write_pending_dataset(record) if ValidationEvidence.new(@operation).pending_dataset?
      ValidationPreparation.generation
    end

    def write_pending_dataset(record)
      template = 'UPDATE departure_acquisitions SET dataset = :dataset::jsonb WHERE id = :id'
      values = { dataset: JSON.generate(StoredDataset.reference(record)), id: @operation.departure_acquisition_id }
      ApplicationRecord.connection.execute(ApplicationRecord.sanitize_sql_array([template, values]))
    end

    def ready(prepared, generation)
      @operation.update!(self.class.ready_attributes(prepared, generation))
    end

    public_class_method def self.ready_attributes(prepared, generation)
      { status: 'ready', generation:, departure_dataset_normalization_id: prepared.record.id, **prepared.projection }
    end

    def stale
      @operation.update!(status: 'stale', error: 'Departure dependencies changed during validation; revalidate')
    end
  end
end
