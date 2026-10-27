# frozen_string_literal: true

module Departures
  # Certificate hashing reads the complete persisted header without materializing annual metadata in Ruby.
  class PersistedDatasetStream < DatasetStream
    private

    def header_metadata
      @header_metadata ||= scope.pick(Arel.sql("header - 'sources' - 'captures'"))
    end

    def header_keys
      scope.pluck(Arel.sql('jsonb_object_keys(header)'))
    end

    def scope
      DepartureDatasetNormalization.where(id: record.id)
    end

    def write_header(output, key)
      field = ApplicationRecord.connection.quote(key)
      if scope.pick(Arel.sql("jsonb_typeof(header->#{field})")) == 'array'
        write_array(output, key)
      else
        JSON::State.new(sort_keys: true).generate(scope.pick(Arel.sql("header->#{field}")), JsonOutput.new(output))
      end
    end

    def write_array(output, key)
      output << '['
      JsonArrayReader.header(record.id, key).each_with_index { |value, index| self.class.write_value(output, value, index) }
      output << ']'
    end

    public_class_method def self.write_value(output, value, index)
      output << ',' unless index.zero?
      output << JSON.generate(value, sort_keys: true)
    end
  end
end
