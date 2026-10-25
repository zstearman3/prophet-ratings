# frozen_string_literal: true

module Departures
  # PostgreSQL parses once; the cursor transfers at most 250 original JSON objects per fetch.
  class JsonRows
    BATCH_SIZE = 250

    def initialize(bytes)
      @bytes = bytes
    end

    def each_batch(&)
      return enum_for(:each_batch) unless block_given?

      ApplicationRecord.connection_pool.with_connection do |connection|
        connection.transaction(requires_new: true) { read(connection, &) }
      end
    end

    def self.outcome(bytes)
      new(bytes).each_batch { |_| nil }
      'success'
    rescue ActiveRecord::StatementInvalid
      'malformed_json'
    rescue ArgumentError
      'malformed_envelope'
    end

    private

    def read(connection, &)
      json = connection.quote(@bytes.dup.force_encoding(Encoding::UTF_8))
      connection.execute(<<~SQL.squish)
        DECLARE departure_json_rows NO SCROLL CURSOR FOR
        WITH input AS MATERIALIZED (SELECT #{json}::json AS body)
        SELECT json_typeof(body) AS envelope, element.value::text AS original
        FROM input LEFT JOIN LATERAL json_array_elements(
          CASE WHEN json_typeof(body) = 'array' THEN body ELSE '[]'::json END
        ) AS element(value) ON true
      SQL
      opened = true
      fetch(connection, &)
    ensure
      self.class.close(connection) if opened
    end

    public_class_method def self.close(connection)
      connection.execute('CLOSE departure_json_rows')
    rescue ActiveRecord::StatementInvalid
      nil # A PostgreSQL error already invalidated and closed the transaction cursor.
    end

    def fetch(connection)
      loop do
        batch = connection.exec_query("FETCH FORWARD #{BATCH_SIZE} FROM departure_json_rows").to_a
        break if batch.empty?

        yield self.class.objects(batch)
      end
    end

    public_class_method def self.original_objects(batch)
      batch.select { |entry| entry['original'] }.map { |entry| JSON.parse(entry.fetch('original')) }
    end

    public_class_method def self.objects(batch)
      Contract.check!(batch.all? { |entry| entry.fetch('envelope') == 'array' }, 'Invalid CBBD response envelope')
      rows = original_objects(batch)
      Contract.check!(rows.all?(Hash), 'Invalid CBBD response envelope')
      rows
    end
  end
end
