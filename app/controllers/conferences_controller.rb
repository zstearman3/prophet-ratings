# frozen_string_literal: true

# Serves season-aware conference team ratings tables.
class ConferencesController < ApplicationController
  include RatingsTableSorting

  def index
    render locals: { conferences: Conference.order(:name), seasons: Season.order(year: :desc), season: selected_season }
  end

  def show
    conference = Conference.find(params.expect(:id))
    season = selected_season
    team_seasons = ordered_conference_team_seasons(conference.team_seasons_for_season(season).includes(:team))
    render locals: {
      conference:, season:, seasons: Season.order(year: :desc), expanded: params[:stats] == 'more',
      team_seasons:, has_team_seasons: team_seasons.load.any?
    }
  end

  private

  def selected_season
    return Season.current unless params.key?(:season)

    year = params[:season].to_s
    raise ActiveRecord::RecordNotFound unless /\A\d{4}\z/.match?(year)

    Season.find_by!(year:)
  end
end
