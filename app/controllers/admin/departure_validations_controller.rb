# frozen_string_literal: true

module Admin
  # Uses the departure controller's authentication and bounded loader for lifecycle actions.
  class DepartureValidationsController < DepartureBatchesController
    def revalidate
      operation = DepartureValidation.where(departure_batch_id: batch.id).order(:id).last
      if params[:close_interrupted] == '1' && operation&.status.in?(%w[queued running])
        operation.update!(status: 'failed', error: 'Operator confirmed interrupted validation; revalidate')
      end
      Departures::ValidationPreparation.queue(batch)
      redirect_to admin_departure_batch_path(batch), notice: I18n.t('admin.departure_batches.validation_queued')
    end

    def progress
      operation = DepartureValidation.where(departure_batch_id: batch.id).order(:id).last
      render json: { status: operation&.progress_status || 'needs_validation', updated_at: operation&.updated_at, error: operation&.error }
    end

    def publish
      approval = approved_choices
      PublishDepartureValidationJob.perform_later(approval.id)
      redirect_to admin_departure_batch_path(batch), notice: I18n.t('admin.departure_batches.publication_queued')
    end

    private

    def approved_choices
      fields = params.require(params[:draft_review] ? :draft_review : :review).to_unsafe_h
      Departures::Contract.check!(fields['confirm'] == '1', 'Confirm explicit approval of the saved decisions')
      Departures::ValidationApproval.new(reviewed_operation(fields)).call(reviewer: current_user.email, user: current_user,
                                                                          acknowledgement: fields.slice('acknowledge_gaps'))
    end

    def reviewed_operation(fields)
      operation = DepartureValidation.where(departure_batch_id: batch.id).order(:id).last
      Departures::Contract.check!(operation && fields['review_key'] == operation.id.to_s,
                                  'Departure review changed; reload and review again')
      operation
    end
  end
end
