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
  # Displays the schedule of games for a specified date, including associated predictions, team season data,
  # and the latest team rating snapshots for each team season as of that date.
  # Redirects to the current date with a notice if the date parameter is missing or invalid.
  # Sets instance variables for the selected date, games, ratings configuration version,
  # and a hash of team rating snapshots grouped by team season and snapshot date.
  def schedule
    date = parsed_date_or_redirect(:schedule)
    return unless date

    @date = date
    @games = schedule_games_for(date)
    @ratings_config_version = RatingsConfigVersion.current
    @snapshots_by_team_season_and_date = snapshots_by_team_season_and_date(@games, @ratings_config_version, @date)
  end

  ##
  # Retrieves games scheduled for a specific date with associated betting data.
  # Redirects to the current date with a notice if the date parameter is missing or invalid.
  # Assigns the parsed date and the list of games, including predictions, odds, bet recommendations,
  # and team season data, to instance variables for use in the view.
  def betting
    date = parsed_date_or_redirect(:betting)
    return unless date

    @date = date
    @sort = params[:sort]
    @games = Game.on_schedule_date(date)
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

  def parsed_date_or_redirect(route)
    if params[:date].blank?
      redirect_to date_redirect_path(route), notice: t('games.date_required')
      return
    end

    Date.parse(params[:date])
  rescue ArgumentError
    redirect_to date_redirect_path(route), alert: t('games.invalid_date')
    nil
  end

  def date_redirect_path(route)
    path_helper = route == :betting ? :betting_games_path : :schedule_games_path
    public_send(path_helper, date: Game.current_schedule_date.to_s)
  end

  def schedule_games_for(date)
    Game.on_schedule_date(date)
        .order(:start_time)
        .includes(:predictions, { home_team_game: :team_season }, { away_team_game: :team_season })
  end

  def snapshots_by_team_season_and_date(games, ratings_config_version, date)
    snapshots = TeamRatingSnapshot
                .where(team_season_id: team_season_ids_for(games), ratings_config_version:)
                .where(snapshot_date: ..date)
                .order(:team_season_id, snapshot_date: :desc)

    snapshots.group_by(&:team_season_id).transform_values do |team_snapshots|
      team_snapshots.sort_by { |snapshot| -snapshot.snapshot_date.to_time.to_i }.index_by(&:snapshot_date)
    end
  end

  def team_season_ids_for(games)
    games.flat_map { |game| [game.home_team_game&.team_season_id, game.away_team_game&.team_season_id] }.compact.uniq
  end

  def sort_games(games, sort_type)
    direction = params[:direction] == 'asc' ? 'asc' : 'desc'
    @games = if %w[spread moneyline total].include?(sort_type)
               sort_by_bet_type(games, sort_type, direction)
             else
               games.sort_by(&:start_time)
             end
    @games
  end

  def sort_by_bet_type(games, bet_type, direction)
    sorted_games = games.to_a.sort_by do |game|
      game.current_bet_recommendations.find { |r| r.bet_type == bet_type }&.ev || -999
    end
    direction == 'desc' ? sorted_games.reverse : sorted_games
  end
end
