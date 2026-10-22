# frozen_string_literal: true

module Departures
  # Groups all captured athlete stints; the provider request never filters by team or athlete.
  class CbbdProduction
    def initialize(parsed:, settings:)
      @parsed = parsed.index_by { |source| source.fetch('id') }
      @settings = settings
    end

    def call
      scopes = CbbdDataset::SCOPES.index_with { |scope| scope_tables(scope) }
      scopes.values.flat_map(&:keys).uniq.sort.map { |id| combine(id, scopes) }
    end

    private

    attr_reader :parsed, :settings

    def rows(id)
      parsed.fetch(id).fetch('rows', [])
    end

    def scope_tables(scope)
      normalizer = self.class
      players, teams = normalizer.index_rows(rows("player-#{scope}"), rows("team-#{scope}"), scope)
      normalizer.build_tables(scope, [players, teams], settings.fetch('prior_season_year'))
    end

    public_class_method def self.index_rows(players, teams, scope)
      validate_keys(players, teams, scope)
      key = method(:team_id)
      [players.group_by(&key), teams.index_by(&key)]
    end

    public_class_method def self.build_tables(scope, grouped, season)
      players, teams = grouped
      (players.keys | teams.keys).index_with do |team_id|
        CbbdTeamScope.new(team: teams[team_id], players: players.fetch(team_id, []), scope:, season:).call
      end
    end

    public_class_method def self.team_id(row)
      CbbdValues.id(row.fetch('teamId'))
    end

    public_class_method def self.validate_keys(players, teams, scope)
      Contract.unique!(players.map { |row| row.values_at('athleteId', 'teamId') }, "#{scope} athlete/team rows")
      Contract.unique!(teams.pluck('teamId'), "#{scope} teams")
    end

    def combine(team_id, scopes)
      CbbdTeamProduction.new(team_id:, entries: scopes.transform_values { |tables| tables[team_id] },
                             absent_scopes: absent_scopes(team_id), evidence: settings.fetch('scope_evidence')).call
    end

    def absent_scopes(team_id)
      return [] unless settings.fetch('absent_postseason_team_ids', []).include?(team_id)
      return [] unless parsed.values_at('player-postseason', 'team-postseason').all? { |source| source['failure'].blank? }

      ['postseason']
    end
  end
end
