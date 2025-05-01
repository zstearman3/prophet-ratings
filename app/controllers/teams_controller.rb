# frozen_string_literal: true

# app/controllers/teams_controller.rb
class TeamsController < ApplicationController
  def show
    @team = Team.all.find { |t| t.school.parameterize == params[:school] }
    @season = Season.find_by(year: params[:year]) || Season.current
    @team_season = TeamSeason.find_by!(team: @team, season: @season)
    @config = RatingsConfigVersion.current

    @snapshots = @team_season.team_rating_snapshots
                             .where(ratings_config_version: @config)
                             .order(:snapshot_date)

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

    # For in-memory prediction matching (config-aware)
    snapshot_scope = TeamRatingSnapshot
                     .where(ratings_config_version: @config)
                     .where(team_season: @team_games.map(&:game).flat_map { |g| [g.home_team_season, g.away_team_season] }.uniq)
                     .where('snapshot_date <= ?', @team_games.map(&:game).map(&:start_time).max.to_date)

    @snapshot_lookup = snapshot_scope.group_by(&:team_season_id)

    # Compute current rank (optional)
    latest_snapshot = @snapshots.last
    @rank = if latest_snapshot
              TeamRatingSnapshot
                .where(snapshot_date: latest_snapshot.snapshot_date, ratings_config_version: @config)
                .order(rating: :desc)
                .pluck(:team_season_id)
                .index(@team_season.id) + 1
            end
  end
end
