# frozen_string_literal: true

module Departures
  # Ordered JSON header entries streamed inside their owner's transaction.
  class JsonArrayReader
    include Enumerable

    def initialize(relation)
      @relation = relation
    end

    def each
      return enum_for(:each) unless block_given?

      SqlCursor.new(@relation).each { |row| yield JSON.parse(row.fetch('value')) }
    end

    def self.sources(attempt_id, key = 'sources')
      SourceMetadata.new(attempt_id, key)
    end

    def self.header(record_id, key)
      source = Arel.sql('departure_dataset_normalizations, LATERAL jsonb_array_elements(header->?) ' \
                        'WITH ORDINALITY AS entries(value, ordinal)', key)
      relation = DepartureDatasetNormalization.from(source).where(id: Integer(record_id))
                                              .select(Arel.sql('value, ordinal')).order(Arel.sql('ordinal'))
      new(relation)
    end
  end
end
