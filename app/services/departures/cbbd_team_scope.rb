# frozen_string_literal: true

module Departures
  # Independent per-scope reconciliation prevents offsetting regular/postseason errors.
  class CbbdTeamScope
    def initialize(team:, players:, scope:, season:)
      @team = team
      @players = players.map { |row| CbbdPlayer.new(row, season).call }
      @scope = scope
      @season = season
    end

    def call
      return { 'players' => players, 'complete' => false } unless team

      validate
      values.merge('players' => players, 'complete' => points_known? && players.any? && points.positive? && games.positive?,
                   'raw_team_row' => team)
    end

    private

    attr_reader :team, :players

    def points
      CbbdValues.optional_whole(team.dig('teamStats', 'points', 'total'), "#{@scope} team points")
    end

    def games
      CbbdValues.whole(team.fetch('games'), 'team games')
    end

    def values
      { 'team_points' => points, 'games' => games, 'team_name_source' => Contract.text!(team.fetch('team'), 'team label'),
        'team_game_clock_minutes' => CbbdValues.optional_minutes(team.fetch('totalMinutes')) }
    end

    def validate
      Contract.check!(team.fetch('season') == @season, 'Wrong production season')
      players.each { |player| validate_player(player) }
      validate_points if points.is_a?(Integer)
    end

    def points_known?
      points.is_a?(Integer) && players.all? { |player| player['player_points'].is_a?(Integer) }
    end

    def validate_points
      subtotal = players.pluck('player_points').compact.sum
      consistent = subtotal <= points && (players.empty? || !points_known? || subtotal == points)
      Contract.check!(consistent, "#{@scope} player/team points mismatch")
    end

    def validate_player(player)
      Contract.check!(player['team_name_source'] == team['team'], 'Conflicting player/team labels')
      Contract.check!(player['games'] <= games, 'Player games exceed team games')
    end
  end
end
