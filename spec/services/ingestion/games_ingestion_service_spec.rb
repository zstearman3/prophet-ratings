# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::GamesIngestionService do
  let(:date) { Date.new(2026, 2, 21) }
  let(:scraper) { instance_double(Scraper::GamesScraper, game_count: 1, to_json_in_batches: rows) }
  let(:rows) { [{ home_team: 'Queens (NC)', away_team: 'West Georgia', date:, url: '/game.html' }] }
  let(:enriched_rows) { [rows.first.merge(venue_type: 'home', venue_name: 'Curry Arena')] }
  let(:row_enricher) { instance_double(Ingestion::GameRowEnricher) }

  before do
    allow(Scraper::GamesScraper).to receive(:new).with(date).and_return(scraper)
    allow(Ingestion::GameRowEnricher).to receive(:new).and_return(row_enricher)
    allow(row_enricher).to receive(:call).with(rows).and_return(enriched_rows)
    allow(Importer::GamesImporter).to receive(:import)
  end

  it 'scrapes, enriches, and imports game rows for the date' do
    described_class.new(date:).call

    expect(scraper).to have_received(:to_json_in_batches).with(0, 1)
    expect(Importer::GamesImporter).to have_received(:import).with(enriched_rows)
  end
end
