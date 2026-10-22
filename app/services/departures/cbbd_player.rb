# frozen_string_literal: true

module Departures
  # One retained player/team scope row, without identity inference from labels.
  class CbbdPlayer
    def initialize(row, season)
      @row = row
      @season = season
    end

    def call
      Contract.check!(row.fetch('season') == @season, 'Wrong production season')
      identity.merge(totals, 'raw_player_row' => row)
    end

    private

    attr_reader :row

    def identity
      { 'provider' => 'cbbd', 'provider_athlete_id' => CbbdValues.id(row.fetch('athleteId')),
        'provider_team_id' => CbbdValues.id(row.fetch('teamId')),
        'player_name_source' => Contract.text!(row.fetch('name'), 'player name'),
        'team_name_source' => Contract.text!(row.fetch('team'), 'team name') }
    end

    def totals
      { 'player_points' => CbbdValues.optional_whole(row.fetch('points'), 'player points'),
        'games' => CbbdValues.whole(row.fetch('games'), 'player games'),
        'player_minutes' => CbbdValues.minutes(row.fetch('minutes'), 'player minutes') }
    end
  end
end
