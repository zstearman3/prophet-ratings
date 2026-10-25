# frozen_string_literal: true

module Admin
  # Season-scoped reviews retain their original model even after selection changes.
  class PreseasonPublicationsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin
    before_action :page
    rescue_from ArgumentError, Season::OperationInProgress, ActiveRecord::RecordInvalid, with: :review_error

    def index
      page[:models] = RatingsConfigVersion.order(created_at: :desc)
      page[:publications] = page[:season].preseason_publications.select(:id, :season_id, :ratings_config_version_id, :mode, :status)
                                         .includes(:ratings_config_version).order(id: :desc)
    end

    def select_model
      season = page.fetch(:season)
      PreseasonPublication.select_model(season, RatingsConfigVersion.find(params.require(:model_id)))
      redirect_to admin_preseason_publications_path(season_id: season.id),
                  notice: t('.selected')
    end

    def show
      publication = PreseasonPublicationPage.review(page[:season].preseason_publications).find(params.expect(:id))
      page[:publication] = publication
      page[:report] = PreseasonPublicationPreview.presentation(publication.report)
      page[:published_outputs] = PreseasonPublicationPage.outputs(publication) if publication.status == 'published'
    end

    def progress
      publication = page[:season].preseason_publications.select(:id, :status, :updated_at).find(params.expect(:id))
      render json: { status: publication.status, updated_at: publication.updated_at.iso8601(6) }
    end

    def retry_preview
      show
      publication = page[:publication]
      PreseasonPublicationPreviewQueue.new(publication).call
      redirect_to admin_preseason_publication_path(publication, season_id: page[:season].id)
    end

    def create
      season = page.fetch(:season)
      publication = PreseasonPublication.review!(season, reviewer: current_user, mode: params.require(:mode))
      redirect_to admin_preseason_publication_path(publication, season_id: season.id)
    end

    def publish
      season = page[:season]
      page[:publication] = PreseasonPublicationPage.summary(season.preseason_publications).find(params.expect(:id))
      publication = page.fetch(:publication)
      PreseasonPublicationQueue.new(publication, actor: current_user, fingerprint: params[:fingerprint],
                                                 acknowledge: params[:acknowledge]).call
      redirect_to admin_preseason_publication_path(publication, season_id: season.id)
    end

    private

    def require_admin
      head :not_found unless current_user.admin?
    end

    def page
      @page ||= { season: Season.find(params.expect(:season_id)) }
    end

    def review_error(error)
      page[:error] = error.message
      template = page[:publication] ? :show : :index
      public_send(template)
      render template, status: :unprocessable_content
    end
  end
end
