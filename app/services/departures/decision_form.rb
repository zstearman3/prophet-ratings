# frozen_string_literal: true

module Departures
  # Accepts only captured identities and existing team choices; numeric facts remain read-only.
  class DecisionForm
    def initialize(dataset)
      @dataset = dataset
      @identity = TeamIdentity.new
    end

    def call(rows)
      self.class.validate_rows(rows, dataset.fetch('selections').pluck('selection_key'))
      rows.filter_map { |key, row| decision(key, row) if row['status'].present? }
    end

    def issues(decisions)
      mappings = decisions.index_by { |decision| decision.fetch('selection_key') }
      dataset.fetch('selections', []).to_h do |selection|
        key = selection.fetch('selection_key')
        [key, row_issue(selection, mappings[key])]
      end
    end

    def self.validate_rows(rows, keys)
      Contract.check!(rows.is_a?(Hash) && (rows.keys - keys).empty?, 'Unknown departure selection')
    end

    private

    attr_reader :dataset, :identity

    def row_issue(selection, decision)
      ReviewedSelection.new(selection:, decision:, dataset:, identity:).call
      nil
    rescue ArgumentError, KeyError => error
      error.message
    end

    def decision(key, row)
      fields = row.slice('status', 'reason')
      Contract.check!(Contract::STATUSES.include?(fields['status']), 'Invalid accounting category')
      fields.merge('selection_key' => key, 'evidence_source_ids' => evidence_ids(row['evidence_source_ids']),
                   'stints' => stints(row.fetch('stints', {}))).merge(self.class.known_team(row['team_id']))
    end

    public_class_method def self.known_team(id)
      return {} if id.blank?

      { 'team_name_source' => Team.find(id).school, 'team_source' => 'canonical' }
    end

    def stints(rows)
      rows.values.filter_map do |entry|
        stint(entry) if self.class.selected_stint?(entry)
      end
    end

    public_class_method def self.selected_stint?(entry)
      entry['remove'] != '1' && entry['production_key'].present?
    end

    def stint(entry)
      table, player = production_choices.fetch(entry.fetch('production_key')) do
        raise ArgumentError, 'Unknown captured production identity'
      end
      self.class.stint_identity(table, player, entry.fetch('team_id')).merge(
        'identity_evidence_source_ids' => evidence_ids(entry['identity_evidence_source_ids'])
      )
    end

    public_class_method def self.stint_identity(table, player, id)
      team_id = Integer(id, 10)
      Contract.check!(Team.exists?(team_id), 'Choose an existing team')
      if table['provider']
        return table.slice('provider', 'production_key', 'provider_team_id').merge(
          player.slice('provider_athlete_id'), 'team_id' => team_id
        )
      end
      { 'source_id' => table.fetch('source_id'), 'player_source_url' => player.fetch('player_source_url'), 'team_id' => team_id }
    end

    def production_choices
      @production_choices ||= dataset.fetch('production').flat_map { |table| self.class.table_choices(table) }.to_h.freeze
    end

    public_class_method def self.table_choices(table)
      table.fetch('players').map { |player| [PlayerIdentity.choice(table, player), [table, player]] }
    end

    def evidence_ids(values)
      ids = Array(values).compact_blank
      Contract.unique!(ids, 'evidence source choices')
      Contract.check!((ids - dataset.fetch('sources').pluck('id')).empty?, 'Unknown evidence source')
      ids
    end
  end
end
