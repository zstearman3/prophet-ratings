# frozen_string_literal: true

module Admin
  # Every submitted decision is pinned to a season and processed by the worker.
  class OffseasonReadinessReviewsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin
    before_action :page

    def index
      page[:reviews] = page[:season].offseason_readiness_reviews.order(id: :desc)
      operation = current_operation
      page[:operation] = operation
      if operation&.status == 'completed' && operation.action != 'report'
        return redirect_to admin_offseason_readiness_review_path(operation.offseason_readiness_review_id, season_id: page[:season].id)
      end

      page[:report] = operation.report if operation&.status == 'completed' && operation.action == 'report'
      render :waiting unless page[:report]
    end

    def show
      page[:review] = page[:season].offseason_readiness_reviews.find(params.expect(:id))
      index
    end

    def create
      submitted = params.fetch(:deferrals, ActionController::Parameters.new)
      allowed = %w[recruiting departures schedule venues predictions operations]
      return head :unprocessable_content if (submitted.keys - allowed).any?

      inputs = { fingerprint: params[:fingerprint], acknowledge: params[:acknowledge], deferrals: submitted.permit(*allowed).to_h }
      operation = page[:season].offseason_readiness_operations.create!(actor: current_user, action: 'review', inputs:)
      enqueue_and_redirect(operation)
    end

    def activate_season
      activate('season')
    end

    def activate_model
      activate('model')
    end

    private

    def current_operation
      return if params[:operation_id].blank?

      page[:season].offseason_readiness_operations.find(params.expect(:operation_id))
    end

    def activate(action)
      review = page[:season].offseason_readiness_reviews.find(params.expect(:id))
      operation = page[:season].offseason_readiness_operations.create!(actor: current_user, action:, offseason_readiness_review: review)
      enqueue_and_redirect(operation)
    end

    def enqueue_and_redirect(operation)
      operation.enqueue
      if operation.offseason_readiness_review_id
        redirect_to admin_offseason_readiness_review_path(operation.offseason_readiness_review_id, season_id: page[:season].id,
                                                                                                   operation_id: operation.id)
      else
        redirect_to admin_offseason_readiness_reviews_path(season_id: page[:season].id, operation_id: operation.id)
      end
    end

    def require_admin
      head :not_found unless current_user.admin?
    end

    def page
      @page ||= { season: Season.find(params.expect(:season_id)) }
    end
  end
end
