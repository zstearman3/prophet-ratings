# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Departures::JsonArrayReader do
  let(:season) { create(:season, year: 2026) }
  let(:batch) { legacy_departure_batch(season) }
  let(:attempt) { batch.acquisitions.create!(plan: batch.plan, status: 'completed') }

  it 'preserves every metadata entry and array order across 249, 250 and 251 entry boundaries' do
    [249, 250, 251].each do |count|
      sources = Array.new(count) { |index| { 'id' => "source-#{count - index}", 'extra' => { 'z' => nil, 'a' => [false, [], '雪'] } } }
      overwrite_departure_record(attempt, manifest: { 'sources' => sources })
      sizes = []
      allow(ApplicationRecord.connection).to receive(:exec_query).and_wrap_original do |original, sql, *args, **options|
        original.call(sql, *args, **options).tap { |result| sizes << result.rows.size if sql.include?('LIMIT 250') }
      end
      expect(described_class.sources(attempt.id).to_a).to eq(sources)
      expect(sizes.sum).to eq(count)
      expect(sizes.max).to be <= 250
      RSpec::Mocks.space.proxy_for(ApplicationRecord.connection).reset
    end
  end

  it 'streams persisted header arrays with exact null, empty, extra metadata and canonical key semantics' do
    header = { 'sources' => Array.new(251) { |index| { 'z' => index, 'a' => [nil, false, { '雪' => 'quoted"' }] } },
               'empty' => [], 'null' => nil, 'nested' => { 'z' => [], 'a' => {} } }
    record = DepartureDatasetNormalization.create!(identity: SecureRandom.uuid, header:)
    output = +''
    Departures::PersistedDatasetStream.new(record).write(output)
    expected = header.merge('selections' => [], 'production' => [], 'failures' => [])
    expect(output).to eq(JSON.generate(expected, sort_keys: true))
  end

  it 'closes owned cursors without masking an original Ruby or aborted SQL error' do
    record = DepartureDatasetNormalization.create!(identity: SecureRandom.uuid, header: { 'sources' => [{ 'id' => 'one' }] })
    reader = described_class.header(record.id, 'sources')
    failure = ->(_value) { raise ArgumentError, 'original failure' }
    expect { reader.each(&failure) }.to raise_error(ArgumentError, 'original failure')
    expect { reader.each { ApplicationRecord.connection.execute('SELECT nonexistent_departure_column') } }
      .to raise_error(ActiveRecord::StatementInvalid, /nonexistent_departure_column/)
    expect(ApplicationRecord.connection.select_values("SELECT name FROM pg_cursors WHERE name LIKE 'departure_metadata_%'")).to be_empty
  end
end
