# frozen_string_literal: true

module Departures
  # Fresh acquisition proof never certifies a historical revision without verifying that revision itself.
  class HistoricalValidation
    # An old approval is retained as evidence; validation does not create a new approval.
    Approval = Data.define(:departure_validation, :document, :review_hash)

    def initialize(operation)
      @operation = operation
      @batch = DepartureBatch.select(DepartureBatch.column_names - ['plan']).find(operation.departure_batch_id)
      @revision = nil
    end

    def call(projection)
      return projection unless @batch.status == 'published'

      validate_payload(historical_approval(projection))
      projection.fetch(:choices).merge!('historical_revision_id' => revision.id, 'historical_input_hash' => revision.input_hash)
      projection
    end

    private

    def revision
      @revision ||= OffseasonInputRevision.select(OffseasonInputRevision.column_names - ['payload']).find(@batch.revision_id)
    end

    def working_operation(projection)
      working = @operation.dup
      working.id = @operation.id
      working.assign_attributes(projection)
      working
    end

    def historical_approval(projection)
      document = historical_document(projection.fetch(:choices).fetch('review'))
      Contract.check!(document.fetch('decisions') == @batch.decisions, 'Published departure decisions differ from replay')
      Approval.new(departure_validation: working_operation(projection), document:, review_hash: Contract.digest(document))
    end

    def historical_document(document)
      document.merge('revision_id' => revision.version, 'reviewed_by' => @batch.reviewed_by,
                     'reviewed_at' => @batch.reviewed_at.iso8601(6), 'partial_acknowledgement' => @batch.acknowledgement)
    end

    def validate_payload(approval)
      payload = PreparedPayload.new(approval)
      actual = PersistedPayload.new(revision.id)
      Contract.check!(actual.matches?(payload), 'Published departure payload differs from authenticated evidence')
      validate_hashes(payload, approval, actual)
    end

    def validate_hashes(payload, approval, actual)
      input_hash = revision.input_hash
      Contract.check!(revision.season_id == @batch.season_id && revision.kind == 'departures' &&
                      revision.review_hash == approval.review_hash &&
                      revision.dataset_hash == approval.document.fetch('dataset_revision') && input_hash == payload.digest &&
                      input_hash == actual.digest, 'Published departure hash differs from retained payload')
    end
  end
end
