# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActiveRecord::LogSubscriber do
  it 'filters retained JSON bodies from SQL logs while preserving bound data and ordinary diagnostics' do
    output = StringIO.new
    previous_logger = ActiveRecord::Base.logger
    ActiveRecord::Base.logger = ActiveSupport::Logger.new(output)
    markers = %w[evidence dataset payload inputs report stats result].map do |column|
      marker = "retained-#{column}-body"
      binds = [ActiveRecord::Relation::QueryAttribute.new(column, { 'marker' => marker }, ActiveRecord::Type::Json.new),
               ActiveRecord::Relation::QueryAttribute.new('status', 'publication-probe', ActiveRecord::Type::String.new)]
      result = ActiveRecord::Base.connection.exec_query('SELECT $1::jsonb AS captured, $2::text AS status', 'Departure logging probe',
                                                        binds)
      expect(result.rows.join).to include(marker, 'publication-probe')
      marker
    end
    expect(output.string).to include('Departure logging probe', 'publication-probe', '[FILTERED]')
    expect(output.string).not_to include(*markers)
  ensure
    ActiveRecord::Base.logger = previous_logger
  end
end
