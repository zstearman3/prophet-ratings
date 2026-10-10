# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::HistoricalSyncDay do
  let(:date) { Date.new(2026, 2, 21) }
  let(:season) { create(:season, year: 2026, start_date: date - 1.day, end_date: date) }
  let(:scraper) { instance_double(Scraper::GamesScraper, game_count: 11) }
  let(:enricher) { instance_double(Ingestion::GameRowEnricher) }
  let(:day) { described_class.new(season:, date:, resume: false) }
  let(:rows) do
    Array.new(11) do |index|
      { date:, home_team: "Home #{index}", away_team: "Away #{index}", url: "/game-#{index}.html" }
    end
  end

  before do
    allow(day).to receive(:sleep)
    allow(Scraper::GamesScraper).to receive(:new).with(date).and_return(scraper)
    allow(Ingestion::GameRowEnricher).to receive(:new).and_return(enricher)
    allow(enricher).to receive(:call) { |batch| batch }
  end

  it 'rolls back the first imported batch, retries the whole date, and rescans without duplicating games' do
    allow(scraper).to receive(:to_json_in_batches).with(0, 10).and_return(rows.first(10))
    attempts = 0
    allow(scraper).to receive(:to_json_in_batches).with(10, 1) do
      attempts += 1
      raise Scraper::GamesScraper::SourceError, 'HTTP 503' if attempts == 1

      rows.last(1)
    end
    expect(day.call).to include(status: 'completed', imported_rows: 11, attempts: 2)
    ids = season.games.order(:id).pluck(:id)
    expect(ids.size).to eq(11)
    expect(day.call).to include(status: 'completed', imported_rows: 11, attempts: 3)
    expect(season.games.order(:id).pluck(:id)).to eq(ids)
    expect(GameSyncDate.first).to have_attributes(status: 'completed', last_error: 'Scraper::GamesScraper::SourceError: HTTP 503')
  end

  it 'persists source failures distinctly from recognized empty dates' do
    allow(scraper).to receive(:game_count).and_raise(Scraper::GamesScraper::SourceError, 'unrecognized schedule page')
    expect(day.call).to include(status: 'failed', attempts: 6, error: /unrecognized schedule/)
    expect(GameSyncDate.first).to have_attributes(status: 'failed', completed_at: nil, imported_rows: nil)
    allow(scraper).to receive(:game_count).and_return(0)
    expect(day.call).to include(status: 'completed', imported_rows: 0, attempts: 7)
    expect(GameSyncDate.first.completed_at).to be_present
  end
end
