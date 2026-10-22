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
      page[:publications] = page[:season].preseason_publications.order(id: :desc)
    end

    def select_model
      season = page.fetch(:season)
      PreseasonPublication.select_model(season, RatingsConfigVersion.find(params.require(:model_id)))
      redirect_to admin_preseason_publications_path(season_id: season.id),
                  notice: t('.selected')
    end

    def show
      page[:publication] = page[:season].preseason_publications.find(params.expect(:id))
    end

    def create
      season = page.fetch(:season)
      publication = PreseasonPublication.review!(season, reviewer: current_user, mode: params.require(:mode))
      redirect_to admin_preseason_publication_path(publication, season_id: season.id)
    end

    def publish
      show
      publication = page.fetch(:publication)
      PreseasonPublicationQueue.new(publication, actor: current_user, fingerprint: params[:fingerprint],
                                                 acknowledge: params[:acknowledge]).call
      redirect_to admin_preseason_publication_path(publication, season_id: page[:season].id)
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
      index if template == :index
      render template, status: :unprocessable_content
    end
  end
end
