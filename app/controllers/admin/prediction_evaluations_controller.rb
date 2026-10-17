# frozen_string_literal: true

module Admin
  # Read-only diagnostics; no rating recalculation or forecast generation occurs here.
  class PredictionEvaluationsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin
    rescue_from ArgumentError, Date::Error, with: :invalid_filters

    def show
      @page = listing
      load_report if page[:season] && page[:model]
      render_report
    end

    private

    attr_reader :page

    def render_report
      respond_to do |format|
        format.html
        format.csv { export_csv }
      end
    end

    def export_csv
      evaluator = page[:evaluator]
      return head :unprocessable_content unless evaluator

      send_data evaluator.report.team_csv, filename: 'team-pace-residuals.csv'
    end

    def require_admin
      head :not_found unless current_user.admin?
    end

    def listing
      seasons = Season.order(year: :desc)
      models = RatingsConfigVersion.order(created_at: :desc)
      { seasons:, models:, season: select_record(seasons, :season_id) || seasons.first,
        model: select_record(models, :model_id) || models.find_by(current: true) || models.first }
    end

    def select_record(records, key)
      identifier = params[key].presence
      records.find(identifier) if identifier
    end

    def load_report
      options = { season: page[:season], date_range: date_range, mode: params[:mode].presence || 'pregame' }
      evaluator = ProphetRatings::PredictionEvaluator.new(ratings_config_version: page[:model], **options)
      page.merge!(evaluator:, metrics: evaluator.call)
      load_comparison(options)
    end

    def load_comparison(options)
      model = select_record(page[:models], :comparison_id)
      return unless model

      candidate = ProphetRatings::PredictionEvaluator.new(ratings_config_version: model, **options)
      page.merge!(comparison_model: model, comparison: page[:evaluator].compare(candidate))
    end

    def date_range
      page[:dates] ||= self.class.parse_dates(params, page.fetch(:season))
    end

    public_class_method def self.parse_dates(filters, season)
      bounds = season.start_date..season.end_date
      first = Date.iso8601(filters[:from].presence || bounds.begin.iso8601)
      last = Date.iso8601(filters[:to].presence || bounds.end.iso8601)
      validate_dates(first, last, bounds)
      first..last
    end

    private_class_method def self.validate_dates(first, last, bounds)
      return if first <= last && bounds.cover?(first) && bounds.cover?(last)

      raise ArgumentError, 'Choose an ordered date range within the selected season.'
    end

    def invalid_filters(error)
      render plain: error.message, status: :unprocessable_content
    end
  end
end
