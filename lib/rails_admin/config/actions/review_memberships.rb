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
            review = SeasonMembershipReview.new(@object)
            if request.post?
              begin
                case params[:operation]
                when 'refresh'
                  review.refresh
                when 'refresh_previous'
                  review.refresh(source_year: @object.year - 1)
                when 'correct_memberships'
                  SeasonConferenceCorrection.new(@object).call(@review_values, reviewer: _current_user.email)
                  flash[:success] = I18n.t('admin.actions.review_memberships.corrected')
                when 'approve'
                  review.apply(@review_values, reviewer: _current_user.email)
                  flash[:success] = I18n.t('admin.actions.review_memberships.approved')
                else
                  raise ArgumentError, 'Choose an action using the review form buttons; your entered values have been retained.'
                end
                redirect_to rails_admin.review_memberships_path(model_name: 'season', id: @object.id)
              rescue ArgumentError, ActiveRecord::ActiveRecordError, Season::OperationInProgress,
                     Scraper::ConferenceStandingsScraper::Error, SeasonConferenceAlignment::Error => error
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
