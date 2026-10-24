# frozen_string_literal: true

module Departures
  # Derives review decisions from captured identities and a frozen prior-season team scope.
  class DraftTeamMatches
    DISPLAY_STATUSES = { 'eligible_prior_season' => 'included', 'outside_prior_season' => 'skipped' }.freeze

    def initialize(dataset)
      @dataset = dataset
    end

    def call
      dataset.fetch('selections').map { |selection| decision(selection) }
    end

    def decision(selection)
      resolved = self.class.resolve(selection, dataset)
      decision_fields(resolved, known_stints(resolved))
    end

    def self.status(teams, stints)
      return 'outside_prior_season' if teams.empty?

      stints.any? ? 'eligible_prior_season' : 'unknown_production'
    end

    def self.resolve(selection, dataset)
      original = selection.fetch('source_row')['athleteId']
      id = original || name_match(selection, dataset)
      method = original ? 'provider_id' : ('exact_name_within_college' if id)
      selection.merge('draft_provider_athlete_id' => original, 'provider_athlete_id' => id,
                      'matched_provider_athlete_id' => id, 'match_method' => method)
    end

    def self.name_match(selection, dataset)
      ids = name_candidates(selection, dataset).pluck('provider_athlete_id').uniq
      ids.first if ids.one?
    end

    def self.name_candidates(selection, dataset)
      players = college_players(selection['provider_team_id'], dataset)
      name = normalized_name(selection.fetch('player_name_source'))
      players.select { |player| normalized_name(player.fetch('player_name_source')) == name }
    end

    def self.college_players(provider_id, dataset)
      tables = dataset.fetch('production').select { |table| table['provider_team_id'] == provider_id }
      tables.flat_map { |table| table.fetch('players') }
    end

    def self.validate_decision(selection, decision, dataset)
      return unless CbbdDataset.automatic?(dataset)

      expected = new(dataset).decision(selection)
      Contract.check!(decision == expected, 'Draft/team decisions differ from the frozen source policy')
    end

    def self.normalized_name(name)
      name.unicode_normalize(:nfc).strip.split.join(' ').downcase
    end

    def self.tables(selection, dataset)
      id = selection['provider_athlete_id']
      return [] unless id

      dataset.fetch('production').select { |table| table.fetch('players').pluck('provider_athlete_id').include?(id) }
    end

    def self.candidate_team_ids(selection, dataset)
      providers = (tables(selection, dataset).pluck('provider_team_id') + [selection['provider_team_id']]).compact.uniq
      providers.flat_map { |id| PlayerIdentity.team_candidates(id, dataset:) }.uniq.sort
    end

    def self.reason(status)
      { 'outside_prior_season' => 'Skipped — no matching prior-season team',
        'eligible_prior_season' => 'Reported production for matched prior-season colleges',
        'unknown_production' => 'Matched prior-season college; player production is missing or incomplete' }.fetch(status)
    end

    def self.present(rows, dataset)
      rows.map do |row|
        row.merge('provider_athlete_id' => row.fetch('source_row')['athleteId'],
                  'status' => DISPLAY_STATUSES.fetch(row.fetch('status'), 'unknown_production'), 'college_teams' => colleges(row, dataset))
      end
    end

    def self.colleges(row, dataset)
      tables = tables(row, dataset).index_by { |table| table.fetch('provider_team_id') }
      ids = (tables.keys + [row['provider_team_id']]).compact.uniq
      ids.map { |id| college(row, id, [tables[id], dataset]) }
    end

    def self.college(row, id, context)
      table, dataset = context
      identity = college_identity(id, dataset)
      values = college_values(row, table, identity)
      status = college_status(identity, values)
      identity.merge(values, 'team_name_source' => table&.fetch('team_name_source') || row['affiliation_source'],
                             'status' => DISPLAY_STATUSES.fetch(status, 'unknown_production'), 'reason' => reason(status))
    end

    def self.college_status(identity, values)
      return 'outside_prior_season' unless identity.fetch('included')

      values.fetch('loss_share').is_a?(Numeric) ? 'eligible_prior_season' : 'unknown_production'
    end

    def self.college_identity(id, dataset)
      match = dataset.fetch('team_matches').find { |entry| entry['provider_team_id'] == id }
      { 'provider_team_id' => id, 'team_id' => match&.fetch('team_id'), 'team_name' => match&.fetch('team_name'),
        'included' => match.present? && match['prior_team_season_id'].present? }
    end

    def self.player(table, athlete)
      table&.fetch('players')&.find { |entry| entry['provider_athlete_id'] == athlete }
    end

    def self.college_values(row, table, identity)
      player = player(table, row['provider_athlete_id'])
      known = identity.fetch('included') && player&.fetch('coverage_complete') && table&.fetch('coverage_complete') &&
              player.fetch('games').positive?
      { 'player_points' => player&.fetch('player_points'), 'team_points' => table&.fetch('team_points'),
        'loss_share' => known ? player.fetch('player_points').fdiv(table.fetch('team_points')) : nil }
    end

    private

    attr_reader :dataset

    def decision_fields(selection, stints)
      matcher = self.class
      teams = matcher.candidate_team_ids(selection, dataset)
      status = matcher.status(teams, stints)
      { 'selection_key' => selection.fetch('selection_key'), 'status' => status, 'reason' => matcher.reason(status),
        'evidence_source_ids' => evidence_ids, 'stints' => stints, 'matched_provider_athlete_id' => selection['provider_athlete_id'],
        'match_method' => selection['match_method'], 'unknown_team_ids' => teams - stints.pluck('team_id') }
    end

    def evidence_ids
      dataset.fetch('sources').pluck('id') - dataset.fetch('failures').pluck('id')
    end

    def known_stints(selection)
      athlete = selection['provider_athlete_id']
      self.class.tables(selection, dataset).filter_map { |table| known_stint(table, athlete) }
    end

    def known_stint(table, athlete)
      ids = PlayerIdentity.team_candidates(table.fetch('provider_team_id'), dataset:)
      player = self.class.player(table, athlete)
      return unless ids.one? && table['coverage_complete'] && player['coverage_complete'] && player['games'].positive?

      table.slice('provider', 'production_key', 'provider_team_id').merge('provider_athlete_id' => athlete, 'team_id' => ids.first,
                                                                          'identity_evidence_source_ids' => evidence_ids)
    end
  end
end
