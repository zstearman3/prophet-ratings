# frozen_string_literal: true

module Admin
  # Admin entry point for safe, transactional target-season preparation.
  class OffseasonSetupsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin
    rescue_from ArgumentError, Date::Error, Season::OperationInProgress, ActiveRecord::RecordInvalid, with: :preparation_error

    def show
      @page = self.class.dashboard_page(selected_season)
    end

    def create
      values = params.expect(preparation: %i[year start_date end_date]).to_h
      result = prepare_season(values)
      season = result.season
      redirect_to admin_offseason_setup_path(season_id: season.id),
                  notice: "Season #{season.year} prepared. #{result.team_seasons_created} team seasons added."
    end

    def self.dashboard_page(season)
      today = Date.current
      preparation = { 'year' => season&.year || (today.year + (today.month >= 7 ? 1 : 0)),
                      'start_date' => '', 'end_date' => '' }
      { seasons: Season.order(year: :desc), season:, preparation:,
        steps: season ? OffseasonSetupProgress.new(season).steps : [], error: nil }
    end

    private

    def prepare_season(values)
      year = target_year(values)
      start_date, end_date = target_dates(values)
      SeasonPreparer.new(year:, start_date:, end_date:).call
    end

    def target_year(values)
      year = SeasonPreparer.parse_year(values['year'])
      raise ArgumentError, 'Ending year must be from 2 through 9999.' unless year.between?(2, 9999)

      year
    end

    def target_dates(values)
      start_date = parse_date(values['start_date'], 'Start date')
      end_date = parse_date(values['end_date'], 'End date')
      raise ArgumentError, 'End date must be after start date.' if start_date && end_date && end_date <= start_date

      [start_date, end_date]
    end

    def parse_date(value, label)
      return if value.blank?

      date = begin
        Date.iso8601(value)
      rescue Date::Error
        nil
      end
      return date if date&.iso8601 == value

      raise ArgumentError, "#{label} must use a valid ISO date."
    end

    def require_admin
      head :not_found unless current_user.admin?
    end

    def selected_season
      season_id = params[:season_id]
      return Season.find(season_id) if season_id.present?

      Season.current || Season.order(year: :desc).first
    end

    def preparation_error(error)
      submitted = params.fetch(:preparation, {}).permit(:year, :start_date, :end_date).to_h
      season = Season.find_by(year: submitted['year'])
      @page = self.class.dashboard_page(season).merge(preparation: submitted, error: error.message)
      render :show, status: :unprocessable_content
    end
  end
end
