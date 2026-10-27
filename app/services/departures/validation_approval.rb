# frozen_string_literal: true

module Departures
  # One explicit confirmation freezes the actor, timestamp, document and signed proposal.
  class ValidationApproval
    # One immutable actor/time tuple is shared by approval and its document.
    Actor = Data.define(:reviewer, :user, :fields, :time)

    def initialize(operation)
      @operation = operation
      @actor = nil
    end

    def call(reviewer:, user: nil, acknowledgement: {})
      Contract.text!(reviewer, 'authenticated reviewer')
      @actor = Actor.new(reviewer:, user:, fields: acknowledgement, time: Time.current)
      ValidationLocks.web_transaction { approve }
    end

    private

    def approve
      @operation.lock!('FOR UPDATE NOWAIT')
      Contract.check!(@operation.status.in?(%w[ready publish_failed]) && @operation.current?,
                      'Departure dependencies changed; revalidate')
      @operation.approval ? authenticated_approval : create_approval
    end

    def authenticated_approval
      approval = @operation.approval
      approval.authenticate
      approval
    end

    def create_approval
      Contract.check!(@operation.status == 'ready', 'Revalidate before creating a departure approval')
      document = approved_document
      DepartureApproval.create!(departure_validation: @operation, user: @actor.user, reviewed_by: @actor.reviewer,
                                reviewed_at: @actor.time, document:, review_hash: Contract.digest(document),
                                predecessor_id: predecessor).sign
    end

    def approved_document
      @operation.choices.fetch('review').merge('reviewed_by' => @actor.reviewer, 'reviewed_at' => @actor.time.iso8601(6),
                                               'partial_acknowledgement' => acknowledgement)
    end

    def acknowledgement
      return {} if @operation.choices['automatic']

      CoverageGaps.acknowledgement(@operation.report.fetch('gaps'), @actor.fields, @actor.reviewer)
    end

    def predecessor
      season_id, status = DepartureBatch.where(id: @operation.departure_batch_id).pick(:season_id, :status)
      Contract.check!(status == 'draft', 'Published departure batches are closed; start a correction')
      OffseasonInputRevision.where(season_id:, kind: 'departures').maximum(:id)
    end
  end
end
