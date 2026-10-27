# frozen_string_literal: true

module Admin
  class OffseasonReadinessOperationsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin

    def create
      season = Season.find(params.expect(:season_id))
      review = season.offseason_readiness_reviews.find_by(id: params[:review_id]) if params[:review_id].present?
      return head :not_found if params[:review_id].present? && !review

      operation, created = report_operation(season, review)
      operation.enqueue if created
      redirect_to destination(operation)
    end

    def progress
      operation = scoped_operation
      render json: { status: operation.status }
    end

    def retry
      operation = scoped_operation
      if operation.status == 'failed'
        operation.with_lock do
          operation.update!(status: 'queued', error_message: nil) if operation.status == 'failed'
        end
      end
      operation.enqueue if operation.status.in?(%w[queued running])
      redirect_to destination(operation)
    end

    private

    def report_operation(season, review)
      OffseasonReadinessOperation.transaction do
        key = ActiveRecord::Base.connection.quote("readiness-report:#{season.id}:#{review&.id}")
        ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{key}, 0))")
        existing = OffseasonReadinessOperation.find_by(season:, action: 'report', offseason_readiness_review: review,
                                                       status: %w[queued running])
        if existing
          [existing, false]
        else
          [OffseasonReadinessOperation.create!(season:, actor: current_user, action: 'report',
                                               offseason_readiness_review: review), true]
        end
      end
    end

    def require_admin
      head :not_found unless current_user.admin?
    end

    def scoped_operation
      OffseasonReadinessOperation.where(season_id: params.expect(:season_id)).find(params.expect(:id))
    end

    def destination(operation)
      if operation.offseason_readiness_review_id
        admin_offseason_readiness_review_path(operation.offseason_readiness_review_id, season_id: operation.season_id,
                                                                                       operation_id: operation.id)
      else
        admin_offseason_readiness_reviews_path(season_id: operation.season_id, operation_id: operation.id)
      end
    end
  end
end
