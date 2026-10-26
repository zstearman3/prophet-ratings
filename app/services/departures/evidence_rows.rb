# frozen_string_literal: true

module Departures
  # Fixed-table append-only persistence avoids retaining annual AR objects in transaction/association callbacks.
  module EvidenceRows
    SOURCE_INSERT = <<~SQL.squish.freeze
      INSERT INTO departure_normalized_rows
        (departure_source_normalization_id, ordinal, row_key, provider_team_id, provider_player_id, fact)
      SELECT departure_source_normalization_id, ordinal, row_key, provider_team_id, provider_player_id, fact
      FROM json_to_recordset($1::json) AS entries(
        departure_source_normalization_id bigint, ordinal integer, row_key text,
        provider_team_id bigint, provider_player_id bigint, fact json)
    SQL
    DATASET_INSERT = <<~SQL.squish.freeze
      INSERT INTO departure_dataset_rows (departure_dataset_normalization_id, kind, ordinal, fact)
      SELECT departure_dataset_normalization_id, kind, ordinal, fact
      FROM json_to_recordset($1::json) AS entries(
        departure_dataset_normalization_id bigint, kind text, ordinal integer, fact json)
    SQL

    def self.source(rows)
      return if rows.empty?

      insert(SOURCE_INSERT, rows)
    end

    def self.annual(attributes)
      insert(DATASET_INSERT, [attributes])
    end

    def self.insert(sql, rows)
      Contract.check!(rows.size <= JsonRows::BATCH_SIZE, 'Departure evidence batch exceeds fixed row limit')
      bind = ActiveRecord::Relation::QueryAttribute.new('departure_evidence_rows', JSON.generate(rows), ActiveRecord::Type::String.new)
      ApplicationRecord.connection.exec_query(sql, 'Departure evidence rows', [bind])
    end
    private_class_method :insert
  end
end
