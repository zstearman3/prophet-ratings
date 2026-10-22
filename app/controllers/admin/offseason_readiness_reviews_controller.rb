# frozen_string_literal: true

module Admin
  # All actions are explicitly season scoped; browser parameters never select an activation model.
  class OffseasonReadinessReviewsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin
    before_action :page
    rescue_from ArgumentError, Season::OperationInProgress, ActiveRecord::RecordInvalid, with: :review_error

    def index
      season = page[:season]
      page[:report] = OffseasonReadiness.new(season).call
      page[:reviews] = season.offseason_readiness_reviews.order(id: :desc)
    end

    def show
      page[:review] = page[:season].offseason_readiness_reviews.find(params.expect(:id))
      index
    end

    def create
      season = page[:season]
      review = OffseasonReadinessReview.record!(season, reviewer: current_user, fingerprint: params[:fingerprint],
                                                        acknowledge: params[:acknowledge], deferrals: deferrals)
      redirect_to admin_offseason_readiness_review_path(review, season_id: season.id)
    end

    def activate_season
      activate('season')
    end

    def activate_model
      activate('model')
    end

    private

    def activate(action)
      show
      OffseasonReadinessActivation.new(page.fetch(:review), actor: current_user, action:).call
      redirect_to admin_offseason_readiness_review_path(page[:review], season_id: page[:season].id)
    end

    def deferrals
      submitted = params.fetch(:deferrals, ActionController::Parameters.new)
      allowed = %w[recruiting departures schedule venues predictions operations]
      raise ArgumentError, 'Only displayed optional open checks may be deferred.' if (submitted.keys - allowed).any?

      submitted.permit(:recruiting, :departures, :schedule, :venues, :predictions, :operations).to_h
    end

    def require_admin
      head :not_found unless current_user.admin?
    end

    def page
      @page ||= { season: Season.find(params.expect(:season_id)) }
    end

    def review_error(error)
      page[:error] = error.message
      index
      render(page[:review] ? :show : :index, status: :unprocessable_content)
    end
  end
end
