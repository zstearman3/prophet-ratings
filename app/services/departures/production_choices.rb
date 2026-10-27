# frozen_string_literal: true

module Departures
  # Every captured player remains reachable through bounded ordered pages; submitted numbers are never trusted.
  class ProductionChoices
    PAGE_SIZE = 30

    def initialize(record_id)
      @record_id = Integer(record_id)
    end

    def page(attributes)
      page = [attributes[:players_page].to_i, 0].max
      query = search(attributes[:player_search]).offset(page * PAGE_SIZE).limit(PAGE_SIZE + 1)
      rows = ApplicationRecord.connection.exec_query(query.to_sql)
      { production_options: rows.first(PAGE_SIZE).map { |row| self.class.option(row) },
        players_next: rows.length > PAGE_SIZE, players_page: page }
    end

    def tables(keys)
      return [] if keys.empty?

      query = relation.where("COALESCE(r.fact->>'production_key', r.fact->>'source_id') IN (?)", keys.map do |key|
        key.split('|', 2).first
      end.uniq)
      rows = ApplicationRecord.connection.exec_query(query.to_sql)
      self.class.selected_tables(rows, keys)
    end

    def selected_options(keys)
      tables(keys).flat_map { |table| self.class.table_options(table) }
    end

    def self.selected_tables(rows, keys)
      tables = {}
      rows.each { |row| retain_selected(tables, row, keys) }
      tables.values
    end

    def self.retain_selected(tables, row, keys)
      table, player = decode(row)
      return unless keys.include?(PlayerIdentity.choice(table, player))

      id = row.fetch('row_id')
      tables[id] ||= table.merge('players' => [])
      tables.fetch(id).fetch('players') << player
    end

    def self.table_options(table)
      table.fetch('players').map { |player| option_for(table, player) }
    end

    def self.option(row)
      option_for(*decode(row))
    end

    def self.decode(row)
      [JSON.parse(row.fetch('metadata')), JSON.parse(row.fetch('player'))]
    end

    def self.option_for(table, player)
      ["#{player['player_name_source']} · #{table['team_name_source']} · #{PlayerIdentity.production_key(table)}",
       PlayerIdentity.choice(table, player)]
    end

    private

    def search(value)
      term = value.to_s.first(100)
      term.blank? ? relation : relation.where('player::text ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(term)}%")
    end

    def relation
      source = Arel.sql("departure_dataset_rows r, LATERAL json_array_elements(r.fact->'players') " \
                        'WITH ORDINALITY AS players(player, player_ordinal)')
      DepartureDatasetRow.from(source).where('r.departure_dataset_normalization_id = ? AND r.kind = ?', @record_id, 'production')
                         .select(Arel.sql("r.id AS row_id, (r.fact::jsonb - 'players') AS metadata, player, player_ordinal"))
                         .order(Arel.sql('r.ordinal, player_ordinal'))
    end
  end
end
