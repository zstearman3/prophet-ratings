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
    allow(SyncDailyGamesJob).to receive(:perform_now) { |date| synced_dates << date }
    allow(UpdateRankingsJob).to receive(:perform_later)
    allow(Time.zone).to receive(:today).and_return(today)
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
end
