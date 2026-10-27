# frozen_string_literal: true

module Departures
  # Saving source coverage retains a successor and queues fresh validation; it never approves inputs.
  class PreparedCoverageReview
    def initialize(batch)
      @batch = batch
      @operation = nil
      @attributes = nil
    end

    def save(attributes, reviewer:)
      @attributes = attributes
      DepartureBatch.transaction do
        ValidationPreparation.lock_generation_nowait
        prepare(attributes, reviewer)
      end
      ValidationPreparation.queue(@batch)
    end

    private

    def prepare(attributes, reviewer)
      validate_operation
      attempt = DepartureAcquisition.select(:id, Arel.sql("plan - 'sources' AS plan")).find(@operation.departure_acquisition_id)
      allowed = @operation.choices.fetch('coverage').fetch('no_postseason_teams').pluck('provider_team_id')
      plan = CoverageForm.new(@batch, attributes, reviewer:, attempt:).call(allowed)
      BatchSuccessor.new(@batch).coverage(plan, attempt.id)
    end

    def validate_operation
      @operation = DepartureValidation.where(departure_batch_id: @batch.id).order(:id).last
      Contract.check!(@operation && @operation.id.to_s == @attributes.fetch('review_key') &&
                      @operation.status == 'ready' && @operation.current? &&
                      !@operation.approval && @batch.status == 'draft', 'Departure coverage changed; reload and review again')
    end
  end
end
