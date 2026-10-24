# frozen_string_literal: true

module Departures
  # Retains per-scope reconciliation evidence under the selected extraction policy.
  class CbbdTeamScope
    def initialize(team:, players:, scope:, settings:)
      @team = team
      @players = players.map { |row| CbbdPlayer.new(row, settings.fetch('prior_season_year')).call }
      @scope = scope
      @settings = settings
    end

    def call
      return { 'players' => players, 'complete' => false } unless team

      validate
      result = values.merge('players' => players, 'complete' => complete?,
                            'raw_team_row' => team)
      CbbdDataset.reported_totals?(settings) ? result.merge('production_warnings' => production_warnings) : result
    end

    private

    attr_reader :team, :players, :settings

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
      Contract.check!(team.fetch('season') == settings.fetch('prior_season_year'), 'Wrong production season')
      players.each { |player| validate_player(player) }
      validate_points if points.is_a?(Integer) && !CbbdDataset.reported_totals?(settings)
    end

    def complete?
      known = CbbdDataset.automatic?(settings) ? points.is_a?(Integer) : points_known?
      known && player_rows_complete? && points.positive? && games.positive?
    end

    def player_rows_complete?
      players.any? || (@scope == 'postseason' && CbbdDataset.optional_postseason_players?(settings))
    end

    def points_known?
      points.is_a?(Integer) && players.all? { |player| player['player_points'].is_a?(Integer) }
    end

    def validate_points
      Contract.check!(points_consistent?, "#{@scope} player/team points mismatch")
    end

    def known_points_subtotal
      players.pluck('player_points').compact.sum
    end

    def points_consistent?
      subtotal = known_points_subtotal
      subtotal <= points && (players.empty? || !points_known? || subtotal == points)
    end

    def production_warnings
      return [] unless points.is_a?(Integer) && !points_consistent?

      [{ 'provider_team_id' => CbbdValues.id(team.fetch('teamId')), 'team_name_source' => team.fetch('team'), 'scope' => @scope,
         'team_points' => points, 'known_player_points_subtotal' => known_points_subtotal, 'all_player_points_known' => points_known?,
         'difference' => known_points_subtotal - points, 'reason' => 'player_team_points_mismatch' }]
    end

    def validate_player(player)
      Contract.check!(player['team_name_source'] == team['team'], 'Conflicting player/team labels')
      Contract.check!(player['games'] <= games, 'Player games exceed team games')
    end
  end
end
