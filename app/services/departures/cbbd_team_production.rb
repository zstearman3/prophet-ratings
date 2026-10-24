# frozen_string_literal: true

module Departures
  # Combines independently reconciled disjoint scopes for one exact provider team.
  class CbbdTeamProduction
    def initialize(team_id:, entries:, absent_scopes:, evidence:, optional_player_scopes: [])
      @team_id = team_id
      @entries = entries
      @scope_policy = { absent: absent_scopes.reject { |scope| entries[scope] },
                        optional_players: optional_player_scopes, evidence: }
    end

    def call
      validate_labels
      identity.merge(totals, 'players' => combined_players, 'coverage_complete' => complete?,
                             'scope' => Contract::SCOPE, 'scope_evidence' => @scope_policy.fetch(:evidence), 'scope_rows' => entries)
    end

    private

    attr_reader :entries

    def present
      entries.values.compact
    end

    def identity
      { 'provider' => 'cbbd', 'provider_team_id' => @team_id, 'production_key' => "cbbd/team/#{@team_id}",
        'team_name_source' => labels.first || players.first&.fetch('team_name_source'), 'source_ids' => source_ids }
    end

    def labels
      present.filter_map { |entry| entry['team_name_source'] }.uniq
    end

    def source_ids
      entries.keys.flat_map { |scope| ["player-#{scope}", "team-#{scope}"] }
    end

    def totals
      { 'team_points' => team_points, 'team_minutes' => CbbdValues.minutes(players.pluck('player_minutes').sum, 'team player minutes') }
    end

    def team_points
      covered = entries.all? { |scope, entry| entry ? entry.key?('team_points') : @scope_policy.fetch(:absent).include?(scope) }
      CbbdValues.sum_whole(present, 'team_points') if covered
    end

    def players
      present.flat_map { |entry| entry.fetch('players') }
    end

    def validate_labels
      Contract.check!(labels.size <= 1, 'Conflicting scope team labels')
    end

    def complete?
      entries.all? { |scope, entry| entry ? entry.fetch('complete') : @scope_policy.fetch(:absent).include?(scope) }
    end

    def combined_players
      players.group_by { |player| player.fetch('provider_athlete_id') }.sort.map { |_athlete, stints| combine_player(stints) }
    end

    def combine_player(stints)
      Contract.check!(stints.pluck('player_name_source').uniq.one?, 'Conflicting scope player labels')
      lineage = player_lineage(stints.first.fetch('provider_athlete_id'))
      self.class.player_totals(stints).merge('scope_rows' => lineage, 'coverage_complete' => player_complete?(lineage))
    end

    def player_lineage(athlete)
      entries.compact.transform_values { |entry| self.class.scope_player(entry, athlete) }.compact
    end

    public_class_method def self.scope_player(entry, athlete)
      entry.fetch('players').find { |row| row.fetch('provider_athlete_id') == athlete }
    end

    def player_complete?(lineage)
      complete? && (CbbdDataset::SCOPES - lineage.keys - @scope_policy.fetch(:absent) - @scope_policy.fetch(:optional_players)).empty? &&
        lineage.values.all? { |player| player['player_points'].is_a?(Integer) }
    end

    public_class_method def self.player_totals(stints)
      stints.first.except('raw_player_row').merge('player_points' => CbbdValues.sum_whole(stints, 'player_points'),
                                                  'player_minutes' => CbbdValues.minutes(stints.pluck('player_minutes').sum,
                                                                                         'player minutes'),
                                                  'games' => stints.pluck('games').sum)
    end
  end
end
