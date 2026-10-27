# frozen_string_literal: true

module Departures
  # One original base64 body at a time; a metadata row limit is not a raw-byte bound.
  class EvidenceStream
    def initialize(attempt_id, output)
      @attempt_id = Integer(attempt_id)
      @output = output
    end

    def call
      @output << '{'
      SqlCursor.new(query, fetch_size: 1).each.with_index { |row, index| write_row(row, index) }
      @output << '}'
    end

    private

    def query
      source = Arel.sql('departure_acquisitions, LATERAL jsonb_each(evidence) AS entries(key, value)')
      DepartureAcquisition.from(source).where(id: @attempt_id).select(Arel.sql('key, value')).order(Arel.sql('key COLLATE "C"'))
    end

    def write_row(row, index)
      @output << ',' unless index.zero?
      @output << JSON.generate(row.fetch('key')) << ':'
      JSON::State.new(sort_keys: true).generate(JSON.parse(row.fetch('value')), DatasetStream::JsonOutput.new(@output))
    end
  end
end
