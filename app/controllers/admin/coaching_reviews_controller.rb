# frozen_string_literal: true

module Admin
  # One admin-only screen for discovery, fact correction and annual readiness.
  class CoachingReviewsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin
    before_action :load_review, except: :index
    rescue_from ArgumentError, ActiveRecord::ActiveRecordError, with: :review_error

    def index
      year = params[:year]
      return redirect_to admin_coaching_review_path(Coaching::YearReview.new(year).year) if year.present?

      @years = (CoachingReview.pluck(:year) | CoachingChange.distinct.pluck(:effective_year) | Season.pluck(:year)).sort.reverse
    end

    def show
      @page = workflow.page(params[:page])
    end

    def update
      workflow.save(params.require(:review).to_unsafe_h, intent: params[:intent])
      redirect_to admin_coaching_review_path(workflow.year, page: params[:page]), notice: I18n.t('admin.coaching_reviews.saved')
    end

    def discover
      workflow.queue_discovery
      redirect_to admin_coaching_review_path(workflow.year), notice: I18n.t('admin.coaching_reviews.queued')
    end

    def candidate
      workflow.add_candidate
      redirect_to admin_coaching_review_path(workflow.year), notice: I18n.t('admin.coaching_reviews.added')
    end

    private

    attr_reader :workflow

    def require_admin
      redirect_to root_path unless current_user.admin?
    end

    def load_review
      @workflow = Coaching::YearReview.new(params.expect(:id))
    end

    def review_error(error)
      message = error.message
      return render plain: message, status: :unprocessable_content if !workflow || action_name == 'show'

      @review_error = message
      show
      render :show, status: :unprocessable_content
    end
  end
end
