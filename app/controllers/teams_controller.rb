# frozen_string_literal: true

# app/controllers/teams_controller.rb
class TeamsController < ApplicationController
  def show
    @team = Team.find_by!(slug: params[:slug])
    @season = Season.find_by(year: params[:year]) || Season.current
    @team_season = TeamSeason.find_by!(team: @team, season: @season)
    @config = RatingsConfigVersion.current

    @snapshots = @team_season.team_rating_snapshots
                             .where(ratings_config_version: @config)
                             .order(:snapshot_date)

    @chart_data = @snapshots.map { |s| [s.snapshot_date, s.rating] }

    @team_games = @team_season.team_games
                              .includes(
                                game: [
                                  { home_team_game: :team },
                                  { away_team_game: :team },
                                  { predictions: %i[home_team_snapshot away_team_snapshot] },
                                  :home_team_season,
                                  :away_team_season
                                ]
                              )
                              .order('games.start_time')

    @snapshot_lookup = TeamRatingSnapshot
      .where(ratings_config_version: @config)
      .where(team_season_id: @team_games.map(&:game).flat_map { |g| [g.home_team_season.id, g.away_team_season.id] }.uniq)
      .where('snapshot_date <= ?', @team_games.map(&:game).map(&:start_time).max.to_date)
      .group_by(&:team_season_id)

      @predictions_by_game = {}

    @team_games.each do |tg|
      game = tg.game
    
      latest_snapshot_date = @snapshots.last&.snapshot_date
      next unless latest_snapshot_date
    
      prediction = game.predictions.find do |p|
          p.home_team_snapshot.ratings_config_version_id == @config.id
      end
    
      @predictions_by_game[game.id] = prediction
    end
  end
end
