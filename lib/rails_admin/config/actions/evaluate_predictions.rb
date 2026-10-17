# frozen_string_literal: true

module RailsAdmin
  module Config
    module Actions
      # Link a season to its read-only evaluation report.
      class EvaluatePredictions < Base
        RailsAdmin::Config::Actions.register(self)
        register_instance_option(:member) { true }
        register_instance_option(:only) { ['Season'] }
        register_instance_option(:http_methods) { [:get] }
        register_instance_option(:link_icon) { 'fas fa-chart-line' }
        register_instance_option :controller do
          proc { redirect_to main_app.admin_prediction_evaluation_path(season_id: @object.id) }
        end
      end
    end
  end
end
