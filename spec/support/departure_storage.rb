# frozen_string_literal: true

# Corruption tests deliberately bypass immutable application APIs at the database boundary.
module DepartureStorageHelpers
  def overwrite_departure_record(record, attributes)
    connection = record.class.connection
    assignments = attributes.map do |column, value|
      value = JSON.generate(value) if value.is_a?(Hash) || value.is_a?(Array)
      "#{connection.quote_column_name(column)} = #{connection.quote(value)}"
    end.join(', ')
    connection.execute("UPDATE #{record.class.quoted_table_name} SET #{assignments} WHERE id = #{Integer(record.id)}")
  end

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
