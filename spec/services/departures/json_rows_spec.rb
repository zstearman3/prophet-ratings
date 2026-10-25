# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Departures::JsonRows do
  it 'fetches a large source in fixed batches with one cursor and preserves JSON semantics' do
    rows = Array.new(701) { |index| { 'number' => index, 'float' => 1.25e-7, 'escaped' => "雪\\\"}{\n" } }
    queries = []
    listener = ->(_name, _start, _finish, _id, payload) { queries << payload.fetch(:sql) }
    batches = []
    ActiveSupport::Notifications.subscribed(listener, 'sql.active_record') do
      described_class.new(JSON.generate(rows)).each_batch { |batch| batches << batch }
    end
    expect(batches.map(&:size)).to eq([250, 250, 201])
    expect(batches.flatten).to eq(rows)
    expect(queries.grep(/DECLARE departure_json_rows/).size).to eq(1)
    expect(queries.grep(/FETCH FORWARD/).size).to eq(4)
    expect(queries.grep(/CLOSE departure_json_rows/).size).to eq(1)
  end

  it 'validates empty and malformed envelopes without accepting trailing corruption' do
    expect(described_class.outcome('[]')).to eq('success')
    ['{}', 'null', '[1]', '[{} ,null]'].each do |body|
      expect(described_class.outcome(body)).to eq('malformed_envelope')
    end
    ['[{}] trailing', '[', '[{},]'].each do |body|
      expect(described_class.outcome(body)).to eq('malformed_json')
    end
  end
end
