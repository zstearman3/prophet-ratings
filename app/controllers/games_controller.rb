# frozen_string_literal: true

class GamesController < ApplicationController
  def show
    @game = Game.includes(
      home_team_game: %i[team team_season],
      away_team_game: %i[team team_season],
      predictions: %i[home_team_snapshot away_team_snapshot]
    ).find(params[:id])

    @home_team_game = @game.home_team_game
    @away_team_game = @game.away_team_game

    @prediction = @game.predictions.order(created_at: :desc).first
    @config = RatingsConfigVersion.current
  end

  ##
  # Displays the schedule of games for a specified date, including associated predictions, team season data, and the latest team rating snapshots for each team season as of that date.
  # Redirects to the current date with a notice if the date parameter is missing or invalid.
  # Sets instance variables for the selected date, games, ratings configuration version, and a hash of team rating snapshots grouped by team season and snapshot date.
  def schedule
    redirect_to schedule_games_path(date: Date.current.to_s), notice: 'Date is required.' and return if params[:date].blank?

    begin
      date = Date.parse(params[:date])
    rescue ArgumentError
      redirect_to schedule_games_path(date: Date.current.to_s), alert: 'Invalid date.' and return
    end
    @date = date
    @games = Game.where(start_time: date.all_day)
                 .order(:start_time)
                 .includes(:predictions, { home_team_game: :team_season }, { away_team_game: :team_season })

    @ratings_config_version = RatingsConfigVersion.current
    team_season_ids = @games.map { |g| g.home_team_game&.team_season_id } +
                      @games.map { |g| g.away_team_game&.team_season_id }
    team_season_ids.compact!
    team_season_ids.uniq!

    # Preload all snapshots for these team_season_ids, config version, and <= date
    snapshots = TeamRatingSnapshot
                .where(team_season_id: team_season_ids, ratings_config_version: @ratings_config_version)
                .where('snapshot_date <= ?', @date)
                .order(:team_season_id, snapshot_date: :desc)

    # Build a hash: { [team_season_id, date] => snapshot }
    @snapshots_by_team_season_and_date = {}
    snapshots.group_by(&:team_season_id).each do |ts_id, snaps|
      # For each date, keep the latest snapshot up to that date
      snaps.sort_by! { |s| -s.snapshot_date.to_time.to_i }
      snaps_by_date = {}
      snaps.each do |snap|
        snaps_by_date[snap.snapshot_date] ||= snap
      end
      @snapshots_by_team_season_and_date[ts_id] = snaps_by_date
    end
  end

  ##
  # Retrieves games scheduled for a specific date with associated betting data.
  # Redirects to the current date with a notice if the date parameter is missing or invalid.
  # Assigns the parsed date and the list of games, including predictions, odds, bet recommendations, and team season data, to instance variables for use in the view.
  def betting
    redirect_to betting_games_path(date: Date.current.to_s), notice: 'Date is required.' and return if params[:date].blank?

    begin
      date = Date.parse(params[:date])
    rescue ArgumentError
      redirect_to betting_games_path(date: Date.current.to_s), alert: 'Invalid date.' and return
    end

    @date = date
    @sort = params[:sort]
    @games = Game.where(start_time: date.all_day)
                 .order(:start_time)
                 .includes(
                   :predictions,
                   :game_odd,
                   :current_bet_recommendations,
                   { home_team_game: :team_season },
                   { away_team_game: :team_season }
                 )

    @games = sort_games(@games, @sort)
  end

  private

  def sort_games(games, _sort)
    direction = params[:direction] == 'asc' ? 'asc' : 'desc'
    case params[:sort]
    when 'spread'
      @games = games.to_a.sort_by { |g| g.current_bet_recommendations.find { |r| r.bet_type == 'spread' }&.ev || -999 }
      @games.reverse! if direction == 'desc'
    when 'moneyline'
      @games = games.to_a.sort_by { |g| g.current_bet_recommendations.find { |r| r.bet_type == 'moneyline' }&.ev || -999 }
      @games.reverse! if direction == 'desc'
    when 'total'
      @games = games.to_a.sort_by { |g| g.current_bet_recommendations.find { |r| r.bet_type == 'total' }&.ev || -999 }
      @games.reverse! if direction == 'desc'
    else
      @games = games.sort_by(&:start_time)
    end
    @games
  end
end
