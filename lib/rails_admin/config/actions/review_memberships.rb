# frozen_string_literal: true

module RailsAdmin
  module Config
    module Actions
      # Admin-only review of scraped proposals before any membership/roster writes.
      class ReviewMemberships < Base
        RailsAdmin::Config::Actions.register(self)

        register_instance_option(:member) { true }
        register_instance_option(:only) { ['Season'] }
        register_instance_option(:http_methods) { %i[get post] }
        register_instance_option(:link_icon) { 'fas fa-list-check' }

        register_instance_option :controller do
          proc do
            @review_error = nil
            @review_values = params[:review]&.to_unsafe_h || {}
            if request.post?
              begin
                result = SeasonMembershipAdminAction.new(@object, reviewer: _current_user.email).call(params.to_unsafe_h)
                @school_import = result.school
                if @school_import
                  render :review_memberships
                else
                  flash[:success] = I18n.t("admin.actions.review_memberships.#{result.notice}") if result.notice
                  redirect_to rails_admin.review_memberships_path(model_name: 'season', id: @object.id)
                end
              rescue ArgumentError, ActiveRecord::ActiveRecordError, Season::OperationInProgress,
                     Scraper::ConferenceStandingsScraper::Error, SeasonConferenceAlignment::Error => error
                @school_import = params[:school_import]&.to_unsafe_h if params[:operation] == 'save_school'
                @review_error = error.message
                @object.reload
                render :review_memberships, status: :unprocessable_content
              end
            else
              render :review_memberships
            end
          end
        end
      end
    end
  end
end
