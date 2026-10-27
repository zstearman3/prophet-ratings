# frozen_string_literal: true

module Departures
  # Fixed-size row scans retain selected stints and all schools for automatically matched athletes.
  class ProductionProjection
    def initialize(record, data, decisions)
      @record = record
      @data = data
      @context = self.class.context(data.fetch('selections'), decisions)
    end

    def call
      tables = read
      CbbdDataset.automatic?(@data) && resolve(tables).any? ? read : tables
    end

    private

    public_class_method def self.context(selections, decisions)
      { keys: decisions.flat_map { |decision| stint_keys(decision) },
        athletes: selections.pluck('provider_athlete_id').compact, colleges: selections.pluck('provider_team_id').compact }
    end

    public_class_method def self.stint_keys(decision)
      decision.fetch('stints', []).map { |stint| PlayerIdentity.production_key(stint) }
    end

    def read
      tables = []
      @record.rows.where(kind: 'production').order(:ordinal).skip_query_cache!.find_each(batch_size: JsonRows::BATCH_SIZE) do |row|
        table = row.fact
        tables << table if relevant?(table)
      end
      tables
    end

    def resolve(tables)
      data = @data.merge('production' => tables)
      resolved = data.fetch('selections').map { |selection| DraftTeamMatches.resolve(selection, data) }
      add_athletes(resolved)
    end

    def add_athletes(resolved)
      athletes = @context.fetch(:athletes)
      additional = resolved.pluck('provider_athlete_id').compact - athletes
      athletes.concat(additional)
      additional
    end

    def relevant?(table)
      @context.fetch(:keys).include?(PlayerIdentity.production_key(table)) ||
        @context.fetch(:colleges).include?(table['provider_team_id']) ||
        table.fetch('players').any? { |player| @context.fetch(:athletes).include?(player['provider_athlete_id']) }
    end
  end
end
