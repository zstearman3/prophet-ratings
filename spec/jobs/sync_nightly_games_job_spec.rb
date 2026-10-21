# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SyncNightlyGamesJob do
  let(:today) { Date.new(2026, 2, 3) }
  let(:synced_dates) { [] }
  let(:season) do
    create(
      :season,
      :current,
      year: 2026,
      start_date: Date.new(2025, 11, 1),
      end_date: Date.new(2026, 2, 5)
    )
  end

  before do
    allow(Ingestion::GamesIngestionService).to receive(:new) do |date:, **|
      synced_dates << date
      instance_double(Ingestion::GamesIngestionService, call: { imported_rows: 0, games: [] })
    end
    allow(UpdateRankingsJob).to receive(:perform_later)
    allow(Game).to receive(:current_schedule_date).and_return(today)
  end

  it 'does not select an unactivated season when no current season exists' do
    create(:season, year: 2027)
    described_class.perform_now
    expect(Ingestion::GamesIngestionService).not_to have_received(:new)
  end

  it 'syncs the recent past lookback window and all upcoming scheduled dates' do
    described_class.perform_now(season.id)

    expect(synced_dates).to eq(
      [
        Date.new(2026, 2, 1),
        Date.new(2026, 2, 2),
        Date.new(2026, 2, 3),
        Date.new(2026, 2, 4),
        Date.new(2026, 2, 5)
      ]
    )
    expect(UpdateRankingsJob).to have_received(:perform_later).with(season.id)
  end

  it 'clips both sync windows to the season boundaries' do
    short_season = create(
      :season,
      year: 2027,
      start_date: Date.new(2026, 2, 2),
      end_date: Date.new(2026, 2, 4)
    )

    described_class.perform_now(short_season.id)

    expect(synced_dates).to eq(
      [
        Date.new(2026, 2, 2),
        Date.new(2026, 2, 3),
        Date.new(2026, 2, 4)
      ]
    )
  end

  it 'supports limiting the future sync window' do
    described_class.perform_now(season.id, future_end_date: Date.new(2026, 2, 4))

    expect(synced_dates).to eq(
      [
        Date.new(2026, 2, 1),
        Date.new(2026, 2, 2),
        Date.new(2026, 2, 3),
        Date.new(2026, 2, 4)
      ]
    )
  end

  it 'can skip enqueuing rankings generation' do
    described_class.perform_now(season.id, enqueue_rankings: false)

    expect(UpdateRankingsJob).not_to have_received(:perform_later)
  end

  it 'does not enqueue rankings when scraper ingestion is incomplete' do
    failure = instance_double(Ingestion::GamesIngestionService, call: { imported_rows: 0, games: [{ outcome: 'unmatched' }] })
    allow(Ingestion::GamesIngestionService).to receive(:new).and_return(failure)
    allow(Ingestion::HistoricalSyncDay).to receive(:new).and_wrap_original do |original, **arguments|
      original.call(**arguments).tap { |day| allow(day).to receive(:sleep) }
    end
    expect { described_class.new.perform(season.id) }.to raise_error(SyncFullSeasonGamesJob::IncompleteSync)
    expect(UpdateRankingsJob).not_to have_received(:perform_later)
  end
end
