# frozen_string_literal: true

# Corruption tests deliberately bypass immutable application APIs at the database boundary.
module DepartureStorageHelpers
  def corrupt_departure_capture(id, bytes)
    connection = DepartureSourceCapture.connection
    connection.execute("UPDATE departure_source_captures SET body = #{connection.quote(bytes)} WHERE id = #{Integer(id)}")
  end

  def corrupt_departure_fact(row, fact)
    connection = row.class.connection
    table = row.class.quoted_table_name
    connection.execute("UPDATE #{table} SET fact = #{connection.quote(JSON.generate(fact))}::json WHERE id = #{Integer(row.id)}")
  end
end

RSpec.configure do |config|
  config.include DepartureStorageHelpers
end
