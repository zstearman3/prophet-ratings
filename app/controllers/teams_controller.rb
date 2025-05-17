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

    # Stat selection for chart
    stat_param = params[:stat].presence || 'rating'
    stat_options = {
      'rating' => 'Rating',
      'adj_offensive_efficiency' => 'Adj ORtg',
      'adj_defensive_efficiency' => 'Adj DRtg',
      'adj_pace' => 'Adj Pace',
      'adj_three_pt_proficiency' => 'Adj 3PT Proficiency',
      'adj_defensive_rebound_rate' => 'Adj DRB Rate',
      'adj_offensive_rebound_rate' => 'Adj ORB Rate',
      'adj_effective_fg_percentage' => 'Adj eFG%',
      'adj_effective_fg_percentage_allowed' => 'Adj eFG% Allowed',
      'adj_turnover_rate' => 'Adj TO Rate',
      'adj_turnover_rate_forced' => 'Adj TO Rate Forced',
      'adj_free_throw_rate' => 'Adj FTR',
      'adj_free_throw_rate_allowed' => 'Adj FTR Allowed'
    }
    @selected_stat = stat_param
    @selected_stat_title = stat_options[@selected_stat] || 'Rating'
    @chart_data = @snapshots.map { |s| [s.snapshot_date, s[@selected_stat] || s.rating] }

    # League average and stddev lines
    avg_attr = case @selected_stat
               when 'rating' then 'average_efficiency'
               when 'adj_offensive_efficiency' then 'avg_adj_offensive_efficiency'
               when 'adj_defensive_efficiency' then 'avg_adj_defensive_efficiency'
               when 'adj_pace' then 'average_pace'
               when 'adj_three_pt_proficiency' then 'avg_adj_three_pt_proficiency'
               when 'adj_defensive_rebound_rate' then 'avg_adj_defensive_rebound_rate'
               when 'adj_offensive_rebound_rate' then 'avg_adj_offensive_rebound_rate'
               when 'adj_effective_fg_percentage' then 'avg_adj_effective_fg_percentage'
               when 'adj_effective_fg_percentage_allowed' then 'avg_adj_effective_fg_percentage_allowed'
               when 'adj_turnover_rate' then 'avg_adj_turnover_rate'
               when 'adj_turnover_rate_forced' then 'avg_adj_turnover_rate_forced'
               when 'adj_free_throw_rate' then 'avg_adj_free_throw_rate'
               when 'adj_free_throw_rate_allowed' then 'avg_adj_free_throw_rate_allowed'
               else 'average'
               end
    stddev_attr = case @selected_stat
                  when 'rating' then 'efficiency_std_deviation'
                  when 'adj_offensive_efficiency' then 'stddev_adj_offensive_efficiency'
                  when 'adj_defensive_efficiency' then 'stddev_adj_defensive_efficiency'
                  when 'adj_pace' then 'pace_std_deviation'
                  when 'adj_three_pt_proficiency' then 'stddev_adj_three_pt_proficiency'
                  when 'adj_defensive_rebound_rate' then 'stddev_adj_defensive_rebound_rate'
                  when 'adj_offensive_rebound_rate' then 'stddev_adj_offensive_rebound_rate'
                  when 'adj_effective_fg_percentage' then 'stddev_adj_effective_fg_percentage'
                  when 'adj_effective_fg_percentage_allowed' then 'stddev_adj_effective_fg_percentage_allowed'
                  when 'adj_turnover_rate' then 'stddev_adj_turnover_rate'
                  when 'adj_turnover_rate_forced' then 'stddev_adj_turnover_rate_forced'
                  when 'adj_free_throw_rate' then 'stddev_adj_free_throw_rate'
                  when 'adj_free_throw_rate_allowed' then 'stddev_adj_free_throw_rate_allowed'
                  else 'std_deviation'
                  end
    avg = @season.try(avg_attr) || 0
    stddev = @season.try(stddev_attr) || 0
    dates = @snapshots.map(&:snapshot_date)
    @avg_line = dates.map { |d| [d, avg] }
    @upper_line = dates.map { |d| [d, avg + stddev] }
    @lower_line = dates.map { |d| [d, avg - stddev] }

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
                       .where(team_season_id: @team_games.map(&:game).flat_map do |g|
                                                [g.home_team_season&.id, g.away_team_season&.id]
                                              end.uniq)
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

    respond_to do |format|
      format.html
      format.turbo_stream if turbo_frame_request?
    end
  end
end
