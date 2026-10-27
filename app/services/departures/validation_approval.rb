# frozen_string_literal: true

module Departures
  # Freezes the authenticated actor and exact reviewed choices, independently of job execution.
  class ValidationApproval
    # One timestamp is shared by the immutable audit row and its approved document.
    Actor = Data.define(:reviewer, :user, :acknowledgement, :time)

    def initialize(operation)
      @operation = operation
      @actor = nil
    end

    def call(reviewer:, user: nil, acknowledgement: {})
      Contract.text!(reviewer, 'authenticated reviewer')
      @actor = Actor.new(reviewer:, user:, acknowledgement:, time: Time.current)
      DepartureApproval.find_by(departure_validation_id: @operation.id) || approve
    end

    private

    def approve
      DepartureValidation.transaction do
        ValidationPreparation.lock_generation_nowait
        @operation.with_lock do
          Contract.check!(@operation.status == 'ready' && @operation.current?, 'Departure dependencies changed; revalidate')
          @operation.approval || create_approval
        end
      end
    end

    def create_approval
      document = approved_document
      DepartureApproval.create!(departure_validation: @operation, user: @actor.user, reviewed_by: @actor.reviewer, reviewed_at: @actor.time,
                                document:, review_hash: Contract.digest(document), predecessor_id: predecessor)
    end

    def predecessor
      season_id, status = DepartureBatch.where(id: @operation.departure_batch_id).pick(:season_id, :status)
      Contract.check!(status == 'draft', 'Published departure batches are closed; start a correction')
      OffseasonInputRevision.where(season_id:, kind: 'departures').maximum(:id)
    end

    def approved_document
      @operation.choices.fetch('review').merge('reviewed_by' => @actor.reviewer, 'reviewed_at' => @actor.time.iso8601(6),
                                               'partial_acknowledgement' => acknowledgement)
    end

    def acknowledgement
      return {} if @operation.choices['automatic']

      CoverageGaps.acknowledgement(@operation.report.fetch('gaps'), @actor.acknowledgement, @actor.reviewer)
    end
  end
end
