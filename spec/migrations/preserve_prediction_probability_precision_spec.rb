# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261020000000_preserve_prediction_probability_precision')

RSpec.describe PreservePredictionProbabilityPrecision do
  it 'widens stored legacy values without rewriting metadata or narrowing on rollback' do
    connection = ActiveRecord::Base.connection
    # A temporary table shadows only this connection's disposable fixture table.
    connection.execute(<<~SQL.squish)
      CREATE TEMPORARY TABLE predictions (
        id integer PRIMARY KEY, home_win_probability numeric(5,4),
        calculation_context jsonb, ratings_config_version_id bigint, updated_at timestamp
      )
    SQL
    [0, 1, 0.1234, 0.9999, nil].each_with_index do |value, index|
      connection.execute(<<~SQL.squish)
        INSERT INTO predictions VALUES (
          #{index}, #{connection.quote(value)}, '{"legacy":true}', 12, '2026-01-01 12:00:00'
        )
      SQL
    end
    before = connection.select_all('SELECT * FROM predictions ORDER BY id').to_a
    described_class.new.up
    after = connection.select_all('SELECT * FROM predictions ORDER BY id').to_a
    expect(after.pluck('home_win_probability')).to eq(before.map { |row| row['home_win_probability']&.to_f })
    expect(after.map { |row| row.except('home_win_probability') }).to eq(before.map { |row| row.except('home_win_probability') })
    type = connection.select_value('SELECT pg_typeof(home_win_probability)::text FROM predictions LIMIT 1')
    expect(type).to eq('double precision')
    expect { described_class.new.down }.to raise_error(ActiveRecord::IrreversibleMigration)
  ensure
    connection.execute('DROP TABLE IF EXISTS pg_temp.predictions')
  end
end
