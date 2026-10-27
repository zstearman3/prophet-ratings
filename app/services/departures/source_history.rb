# frozen_string_literal: true

module Departures
  # Original provenance and downloads remain available without loading annual JSON columns into a model.
  class SourceHistory
    PAGE_SIZE = 20

    def initialize(batch, attributes = {})
      @batch = batch
      @attributes = attributes
    end

    def call
      return { sources: [], sources_next: false, source_attempt: nil, sources_page: 0 } unless selected_attempt

      page = [@attributes[:sources_page].to_i, 0].max
      rows = ApplicationRecord.connection.exec_query(sources.offset(page * PAGE_SIZE).limit(PAGE_SIZE + 1).to_sql)
      { sources: rows.first(PAGE_SIZE).map { |row| JSON.parse(row.fetch('value')) }, sources_next: rows.length > PAGE_SIZE,
        source_attempt: selected_attempt, sources_page: page }
    end

    def source(id)
      rows = ApplicationRecord.connection.exec_query(sources.where("value->>'id' = ?", id).limit(2).to_sql).to_a
      self.class.single_source(rows)
    end

    def self.single_source(rows)
      Contract.check!(rows.one?, 'Unknown or ambiguous retained source')
      JSON.parse(rows.fetch(0).fetch('value'))
    end

    private

    def selected_attempt
      id = @attributes[:attempt_id]
      attempts = @batch.acquisitions.select(:id)
      @selected_attempt ||= id.present? ? attempts.find(id) : attempts.order(:id).last
    end

    def sources
      source = Arel.sql("departure_acquisitions, LATERAL jsonb_array_elements(COALESCE(manifest->'sources', '[]'::jsonb) || " \
                        "COALESCE(manifest->'captures', '[]'::jsonb)) WITH ORDINALITY AS sources(value, ordinal)")
      DepartureAcquisition.from(source).where(id: selected_attempt.id).select(Arel.sql('value, ordinal')).order(Arel.sql('ordinal'))
    end
  end
end
