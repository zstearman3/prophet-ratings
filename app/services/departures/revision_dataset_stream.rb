# frozen_string_literal: true

module Departures
  # Streams the dataset retained inside an old revision independently of normalization records.
  class RevisionDatasetStream
    def initialize(scope, output)
      @scope = scope
      @output = output
    end

    def write
      @output << '{'
      keys.each_with_index { |key, index| write_entry(key, index) }
      @output << '}'
    end

    private

    def keys
      source = Arel.sql("offseason_input_revisions, LATERAL jsonb_object_keys(payload->'dataset') AS entries(key)")
      @scope.from(source).order(Arel.sql('key COLLATE "C"')).pluck(Arel.sql('key'))
    end

    def write_entry(key, index)
      PersistedPayload.write_key(@output, key, index)
      type = @scope.pick(Arel.sql("jsonb_typeof(payload->'dataset'->?)", key))
      type == 'array' ? write_array(key) : write_value(@scope.pick(Arel.sql("payload->'dataset'->?", key)))
    end

    def write_array(key)
      @output << '['
      SqlCursor.new(array_relation(key)).each.with_index do |row, index|
        PersistedDatasetStream.write_value(@output, JSON.parse(row.fetch('value')), index)
      end
      @output << ']'
    end

    def array_relation(key)
      source = Arel.sql("offseason_input_revisions, LATERAL jsonb_array_elements(payload->'dataset'->?) " \
                        'WITH ORDINALITY AS entries(value, ordinal)', key)
      @scope.from(source).select(Arel.sql('value, ordinal')).order(Arel.sql('ordinal'))
    end

    def write_value(entry)
      JSON::State.new(sort_keys: true).generate(entry, DatasetStream::JsonOutput.new(@output))
    end
  end
end
