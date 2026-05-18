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
    result = described_class.new(date:).call

    expect(scraper).to have_received(:to_json_in_batches).with(0, 1)
    expect(Importer::GamesImporter).to have_received(:import).with(enriched_rows)
    expect(result[:imported_rows]).to eq(1)
  end

  it 'falls back to the default batch size when initialized with an invalid batch size' do
    result = described_class.new(date:, batch_size: 0).call

    expect(scraper).to have_received(:to_json_in_batches).with(0, 1)
    expect(result[:imported_rows]).to eq(1)
  end

  it 'supports team-specific scraping through the same enrichment and import path' do
    team = build_stubbed(:team)
    team_rows = [rows.first.merge(home_team: team.school)]
    allow(scraper).to receive(:to_json_for_team).with(team).and_return(team_rows)
    allow(row_enricher).to receive(:call).with(team_rows).and_return(enriched_rows)

    result = described_class.new(date:, team:).call

    expect(row_enricher).to have_received(:call).with(team_rows).once
    expect(Importer::GamesImporter).to have_received(:import).with(enriched_rows).once
    expect(result[:imported_rows]).to eq(1)
  end
end
