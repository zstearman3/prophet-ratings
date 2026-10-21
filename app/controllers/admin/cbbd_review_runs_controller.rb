# frozen_string_literal: true

module Admin
  # All evidence and mutations remain behind the existing administrative session.
  class CbbdReviewRunsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin
    before_action :load_run, only: %i[show update compare apply]
    rescue_from ArgumentError, Ingestion::Cbbd::CaptureStore::IntegrityError,
                Ingestion::Reconciliation::Apply::RetryableConflict, ActiveRecord::RecordInvalid, with: :review_error

    def index
      @listing = CbbdReviewRun.listing(params[:season_id])
    end

    def show
      @comparison = run.review_comparison(params[:version])
      comparison&.verify_artifact
      @page = Ingestion::Reconciliation::ReviewPage.new(comparison&.report, navigation.stringify_keys)
    end

    def create
      run = CbbdReviewRun.create!(season: Season.find(params.expect(:season_id)), **acquisition_attributes)
      AcquireCbbdReviewJob.perform_later(run.id)
      redirect_to admin_cbbd_review_run_path(run), notice: I18n.t('admin.cbbd_review_runs.queued')
    end

    def update
      review.save(submission.merge('filters' => navigation.stringify_keys))
      redirect_to admin_cbbd_review_run_path(run, **navigation), notice: I18n.t('admin.cbbd_review_runs.saved')
    end

    def compare
      review.compare
      redirect_to admin_cbbd_review_run_path(run), notice: I18n.t('admin.cbbd_review_runs.compared')
    end

    def apply
      review.apply(submission, reviewer: current_user)
      redirect_to admin_cbbd_review_run_path(run), notice: I18n.t('admin.cbbd_review_runs.applied')
    end

    def self.browser_rows(value)
      rows = value.fetch('rows', [])
      value.merge('rows' => rows.is_a?(Hash) ? rows.values : rows)
    end

    helper_method :page

    private

    attr_reader :run, :comparison, :page

    def acquisition_attributes
      { start_date: params.expect(:start_date), end_date: params.expect(:end_date),
        maximum_requests: params[:maximum_requests].presence || ENV.fetch('CBBD_MAX_REQUESTS', nil),
        retries: params[:retries].presence || ENV.fetch('CBBD_RETRIES', nil) }
    end

    def submission
      value = params.expect(review: [:comparison_id, :draft_revision, :reason, :confirm, :bulk,
                                     { rows: [%i[entity external_id local_id action supersedes_external_id selected deferred]] }]).to_h
      self.class.browser_rows(value)
    end

    def navigation
      params.permit(:entity, :status, :q, :page).to_h.symbolize_keys
    end

    def review
      Ingestion::Reconciliation::RunReview.new(run)
    end

    def load_run
      @run = CbbdReviewRun.find(params.expect(:id))
    end

    def require_admin
      redirect_to root_path unless current_user.admin?
    end

    def review_error(error)
      render plain: error.message, status: :unprocessable_content
    end
  end
end
