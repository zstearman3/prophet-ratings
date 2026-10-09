# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::FutureScheduleRefresh do
  let(:today) { Date.new(2026, 11, 1) }
  let(:season) { create(:season, year: 2027, start_date: today, end_date: today + 20.days) }
  let(:refresh) { described_class.new(season:, start_date: today, end_date: today + 2.days) }
  let(:service) { instance_double(Ingestion::GamesIngestionService, call: { imported_rows: 0, games: [] }) }

  before do
    allow(Game).to receive(:current_schedule_date).and_return(today)
    allow(Ingestion::GamesIngestionService).to receive(:new).and_return(service)
    allow(refresh).to receive(:sleep)
  end

  it 'visits every bounded date regardless of existing future games and leaves activation unchanged' do
    create(:game, season:, start_time: Game.schedule_time_for(today + 15.days), status: :scheduled)
    result = refresh.call
    expect(result[:days].pluck(:date)).to eq((today..(today + 2.days)).to_a)
    expect(result[:failed_dates]).to be_empty
    expect(season.reload).not_to be_current
    expect(Ingestion::GamesIngestionService).to have_received(:new).with(date: today, season:)
  end

  it 'reports source absences on successful dates without deleting records' do
    game = create(:game, season:, start_time: Game.schedule_time_for(today), status: :scheduled)
    result = refresh.call
    expect(result[:absent_ids]).to eq([game.id])
    expect(game.reload).to be_scheduled
  end

  it 'reports exhausted retries separately from successful empty dates and continues' do
    failing = instance_double(Ingestion::GamesIngestionService)
    allow(failing).to receive(:call).and_raise(Scraper::GamesScraper::SourceError, 'unavailable')
    allow(Ingestion::GamesIngestionService).to receive(:new).with(date: today, season:).and_return(failing)
    game = create(:game, season:, start_time: Game.schedule_time_for(today), status: :scheduled)
    result = refresh.call
    expect(result[:failed_dates]).to eq([today])
    expect(result[:days].last).to include(imported_rows: 0, date: today + 2.days)
    expect(result[:absent_ids]).not_to include(game.id)
    expect(failing).to have_received(:call).exactly(4).times
  end

  it 'rolls back a partial date before retrying it' do
    allow(service).to receive(:call) do
      create(:game, season:, start_time: Game.schedule_time_for(today), status: :scheduled)
      raise Scraper::GamesScraper::SourceError, 'second batch failed'
    end
    expect(refresh.call[:failed_dates]).to eq((today..(today + 2.days)).to_a)
    expect(Game.count).to eq(0)
  end

  it 'omits a reliably moved game from absence review after later dates succeed' do
    game = create(:game, season:, start_time: Game.schedule_time_for(today), status: :scheduled)
    allow(service).to receive(:call) do
      game.update!(start_time: Game.schedule_time_for(today + 1.day))
      { imported_rows: 1, games: [{ game_id: game.id, outcome: 'updated' }] }
    end
    expect(refresh.call[:absent_ids]).to be_empty
  end

  it 'rejects missing, reversed, historical and out-of-season windows before ingestion' do
    [[nil, today], [today + 1.day, today], [today - 1.day, today], [today, season.end_date + 1.day]].each do |first, last|
      expect { described_class.new(season:, start_date: first, end_date: last) }.to raise_error(ArgumentError)
    end
    expect(Ingestion::GamesIngestionService).not_to have_received(:new)
  end
end
