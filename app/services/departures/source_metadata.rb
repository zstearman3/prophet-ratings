# frozen_string_literal: true

module Departures
  # Each metadata window finishes before parsing, so source writes keep their own short transactions.
  class SourceMetadata
    include Enumerable

    def initialize(attempt_id, key)
      @attempt_id = Integer(attempt_id)
      @key = key
      @ordinal = 0
    end

    def each(&)
      return enum_for(:each) unless block_given?

      @ordinal = 0
      read_windows(&)
    end

    def self.emit(rows)
      rows.each { |row| yield JSON.parse(row.fetch('value')) }
    end

    private

    def read_windows(&)
      while (rows = window).any?
        @ordinal = Integer(rows.last.fetch('ordinal'))
        self.class.emit(rows, &)
      end
    end

    def window
      ApplicationRecord.connection.exec_query(relation.limit(JsonRows::BATCH_SIZE).to_sql)
    end

    def relation
      source = Arel.sql('departure_acquisitions, LATERAL jsonb_array_elements(manifest->?) ' \
                        'WITH ORDINALITY AS entries(value, ordinal)', @key)
      DepartureAcquisition.from(source).where(id: @attempt_id).where('ordinal > ?', @ordinal)
                          .select(Arel.sql('value, ordinal')).order(Arel.sql('ordinal'))
    end
  end
end
