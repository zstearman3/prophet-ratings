# frozen_string_literal: true

module RailsAdmin
  module Config
    module Actions
      # Entry point from a Season to its database-backed CBBD identity review.
      class ReviewCbbdIdentities < Base
        RailsAdmin::Config::Actions.register(self)
        register_instance_option(:member) { true }
        register_instance_option(:only) { ['Season'] }
        register_instance_option(:http_methods) { [:get] }
        register_instance_option(:link_icon) { 'fas fa-list-check' }
        register_instance_option :controller do
          proc { redirect_to main_app.admin_cbbd_review_runs_path(season_id: @object.id) }
        end
      end
    end
  end
end
