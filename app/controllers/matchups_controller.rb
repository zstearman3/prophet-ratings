# frozen_string_literal: true

class MatchupsController < ApplicationController
  def show
    @team_options = TeamSeason.includes(:team).where(season: Season.current)
                              .order('teams.school asc').map do |s|
      [s.team.school, s.id]
    end
  end

  def submit
    home_team_season = TeamSeason.find_by(id: matchup_params[:home_team_id])
    away_team_season = TeamSeason.find_by(id: matchup_params[:away_team_id])
    config = RatingsConfigVersion.current

    @home_snapshot = TeamRatingSnapshot.where(team_season: home_team_season, ratings_config_version: config)
                                       .order(snapshot_date: :desc).first
    @away_snapshot = TeamRatingSnapshot.where(team_season: away_team_season, ratings_config_version: config)
                                       .order(snapshot_date: :desc).first
    @neutral = matchup_params[:neutral] == '1'
    @upset_modifier = matchup_params[:upset_modifier].presence&.to_f || 1.0
    @predictor = ProphetRatings::GamePredictor.new(
      home_rating_snapshot: @home_snapshot,
      away_rating_snapshot: @away_snapshot,
      neutral: @neutral
    )

    begin
      case params[:action_type]
      when 'predict'
        @prediction = @predictor.call
      when 'simulate'
        @simulation = @predictor.simulate
      end

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to matchup_path, alert: 'Turbo not supported. Please use a compatible browser.' }
      end
    rescue ArgumentError => e
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace('matchup_form', partial: 'shared/error', locals: { message: e.message }),
                 status: :unprocessable_entity
        end
        format.html { redirect_to matchup_path, alert: e.message, status: :unprocessable_entity }
      end
    end
  end

  private

  def matchup_params
    params.permit(
      :action_type,
      :home_team_id,
      :away_team_id,
      :neutral,
      :upset_modifier
    )
  end
end
