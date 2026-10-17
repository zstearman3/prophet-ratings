# frozen_string_literal: true

module RailsAdmin
  module Config
    module Actions
      # A prepared season links directly to its annual coaching review.
      class ReviewCoaching < Base
        RailsAdmin::Config::Actions.register(self)
        register_instance_option(:member) { true }
        register_instance_option(:only) { ['Season'] }
        register_instance_option(:http_methods) { [:get] }
        register_instance_option(:link_icon) { 'fas fa-list-check' }
        register_instance_option :controller do
          proc { redirect_to main_app.admin_coaching_review_path(@object.year) }
        end
      end

      # Coaching years can be discovered before a Season exists.
      class CoachingReviewQueue < Base
        RailsAdmin::Config::Actions.register(self)
        register_instance_option(:collection) { true }
        register_instance_option(:only) { %w[CoachingChange CoachingReview] }
        register_instance_option(:http_methods) { [:get] }
        register_instance_option(:link_icon) { 'fas fa-list-check' }
        register_instance_option :controller do
          proc { redirect_to main_app.admin_coaching_reviews_path }
        end
      end
    end
  end
end
