# frozen_string_literal: true

module Departures
  # Joins one explicitly reviewed roster URL to the parsed official school totals.
  class ProductionStint
    UNITS = { 'player_points' => 'points', 'team_points' => 'points',
              'player_minutes' => 'player_minutes', 'team_minutes' => 'player_minutes' }.freeze

    def initialize(stint:, dataset:, identity:)
      @stint = stint
      @dataset = dataset
      @identity = identity
      @table = production_table
    end

    def call
      ids = stint.fetch('identity_evidence_source_ids')
      ReviewedSelection.evidence(ids, dataset)
      Contract.check!(candidates == [stint.fetch('team_id')], "Unresolved/conflicting team identity; candidates #{candidates}")
      player.merge(table.except('players'), 'team_id' => candidates.first, 'candidate_team_ids' => candidates,
                                            'identity_evidence_source_ids' => ids, 'scope' => Contract::SCOPE, 'units' => UNITS)
    end

    def self.participant(players)
      Contract.check!(players.one?, 'Missing or ambiguous school player identity')
      player = players.first
      Contract.check!(player.fetch('games').positive?, 'No participation: use verified_nonparticipant with evidence')
      player
    end

    private

    attr_reader :stint, :dataset, :identity, :table

    def production_table
      tables = dataset.fetch('production').select { |entry| entry['source_id'] == stint.fetch('source_id') }
      Contract.check!(tables.one?, 'Missing or ambiguous production source')
      tables.first
    end

    def candidates
      source = dataset.fetch('sources').find { |entry| entry['id'] == table.fetch('source_id') }
      identity.candidates(table.fetch('team_name_source'), source: URI.parse(source.fetch('url')).host)
    end

    def player
      players = table.fetch('players').select { |row| row['player_source_url'] == stint.fetch('player_source_url') }
      self.class.participant(players)
    end
  end
end
