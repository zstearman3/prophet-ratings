# frozen_string_literal: true

require 'English'

module Departures
  # Only Rails relations may supply SELECTs; the pinned transaction owns quoted cursor names and bounded fetches.
  class SqlCursor
    include Enumerable

    def initialize(relation, fetch_size: JsonRows::BATCH_SIZE)
      @relation = self.class.checked_relation(relation)
      @fetch_size = SqlCursor.checked_size(fetch_size)
      @connection = ApplicationRecord.connection
      @name = "departure_metadata_#{SecureRandom.hex(6)}"
    end

    def each(&)
      return enum_for(:each) unless block_given?

      @connection.transaction(requires_new: true) { with_cursor { fetch(&) } }
    end

    def self.checked_relation(relation)
      Contract.check!(relation.is_a?(ActiveRecord::Relation), 'Departure cursor requires a bound Rails relation')
      relation
    end

    def self.checked_size(value)
      size = Integer(value)
      Contract.check!(size.between?(1, JsonRows::BATCH_SIZE), 'Invalid departure cursor batch size')
      size
    end

    private

    def with_cursor
      @connection.execute("DECLARE #{ApplicationRecord.connection.quote_column_name(@name)} NO SCROLL CURSOR FOR #{@relation.to_sql}")
      begin
        yield
      ensure
        original_error = $ERROR_INFO
        begin
          close
        rescue ActiveRecord::StatementInvalid
          raise unless original_error
        end
      end
    end

    def fetch(&)
      loop do
        rows = @connection.exec_query("FETCH FORWARD #{@fetch_size.to_i} FROM #{ApplicationRecord.connection.quote_column_name(@name)}")
        break if rows.empty?

        rows.each(&)
      end
    end

    def close
      return if @connection.raw_connection.transaction_status == PG::PQTRANS_INERROR

      @connection.execute("CLOSE #{ApplicationRecord.connection.quote_column_name(@name)}")
    end
  end
end
