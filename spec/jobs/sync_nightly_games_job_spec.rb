# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SyncNightlyGamesJob do
  include ActiveJob::TestHelper

  around do |example|
    adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = adapter
  end

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
    clear_enqueued_jobs
    allow(Ingestion::HistoricalSyncDay).to receive(:new).and_wrap_original do |original, **arguments|
      original.call(**arguments).tap { |day| allow(day).to receive(:sleep) }
    end
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

  def fail_dates(dates, transport: false)
    failure = instance_double(Ingestion::GamesIngestionService)
    if transport
      allow(failure).to receive(:call).and_raise(IOError, 'synthetic unavailable')
    else
      allow(failure).to receive(:call).and_return(imported_rows: 0, games: [{ outcome: 'unmatched' }])
    end
    dates.each { |date| allow(Ingestion::GamesIngestionService).to receive(:new).with(date:, season:).and_return(failure) }
  end

  [false, true].each do |transport|
    it "enqueues rankings once without async renewal after future #{transport ? 'transport' : 'unmatched'} failure" do
      fail_dates([today], transport:)
      create(:ratings_config_version, current: true)
      allow(UpdateRankingsJob).to receive(:perform_later).and_call_original
      operation = -> { described_class.perform_now(season.id) }
      expect(&operation).to raise_error(Ingestion::GameSyncProvider::Incomplete) do |error|
        expect(error.report).to include(complete: false, past_complete: true, future_complete: false,
                                        past_failed_dates: [], future_failed_dates: [today], failed_dates: [today])
      end
      expect(enqueued_jobs.pluck(:job)).to eq([UpdateRankingsJob])
      expect(GameSyncDate.where(status: 'failed').pluck(:schedule_date)).to eq([today])
    end
  end

  it 'keeps past failures retryable and blocks rankings even when future coverage succeeds' do
    fail_dates([today - 1])
    allow(UpdateRankingsJob).to receive(:perform_later).and_call_original
    report = nil
    expect { described_class.new.perform(season.id) }.to raise_error(SyncFullSeasonGamesJob::IncompleteSync) { |error| report = error.report }
    expect(report).to include(past_complete: false, future_complete: true, past_failed_dates: [today - 1], future_failed_dates: [])
    expect(enqueued_jobs).to be_empty
    described_class.perform_now(season.id)
    expect(enqueued_jobs.pluck(:job)).to eq([described_class])
  end

  it 'blocks rankings when both windows fail' do
    fail_dates([today - 1, today])
    expect { described_class.new.perform(season.id) }.to raise_error(SyncFullSeasonGamesJob::IncompleteSync) do |error|
      expect(error.report).to include(past_complete: false, future_complete: false,
                                      past_failed_dates: [today - 1], future_failed_dates: [today])
    end
    expect(UpdateRankingsJob).not_to have_received(:perform_later)
  end

  it 'honors explicit rankings opt-out after successful past and failed future coverage' do
    fail_dates([today])
    expect { described_class.perform_now(season.id, enqueue_rankings: false) }.to raise_error(Ingestion::GameSyncProvider::Incomplete)
    expect(UpdateRankingsJob).not_to have_received(:perform_later)
    expect(enqueued_jobs).to be_empty
  end

  it 'does not newly authorize rankings after a future-only partial failure with no requested past dates' do
    fail_dates([today])
    operation = -> { described_class.perform_now(season.id, past_lookback_days: 0) }
    expect(&operation).to raise_error(Ingestion::GameSyncProvider::Incomplete) do |error|
      expect(error.report).to include(past_complete: true, past_dates: [], future_failed_dates: [today])
    end
    expect(UpdateRankingsJob).not_to have_received(:perform_later)
    expect(enqueued_jobs).to be_empty
  end

  it 'preserves successful future-only run behavior' do
    report = described_class.perform_now(season.id, past_lookback_days: 0)
    expect(report).to include(complete: true, past_complete: true, future_complete: true, past_dates: [])
    expect(UpdateRankingsJob).to have_received(:perform_later).with(season.id)
  end

  it 'retains the original Eastern boundary when acquisition crosses midnight', :aggregate_failures do
    create(:ratings_config_version, current: true)
    allow(UpdateRankingsJob).to receive(:perform_later).and_call_original
    calculator = instance_double(ProphetRatings::OverallRatingsCalculator, call: true)
    allow(ProphetRatings::OverallRatingsCalculator).to receive(:new).and_return(calculator)
    allow(GenerateNightlyPredictionsJob).to receive(:perform_later)
    service = instance_double(Ingestion::GamesIngestionService, call: { imported_rows: 0, games: [] })
    failure = instance_double(Ingestion::GamesIngestionService, call: { imported_rows: 0, games: [{ outcome: 'unmatched' }] })
    allow(Ingestion::GamesIngestionService).to receive(:new) do |date:, **|
      allow(Game).to receive(:current_schedule_date).and_return(today + 1)
      date == today ? failure : service
    end
    operation = -> { described_class.perform_now(season.id) }
    expect(&operation).to raise_error(Ingestion::GameSyncProvider::Incomplete) do |error|
      expect(error.report).to include(schedule_date: today, past_dates: [today - 2, today - 1],
                                      future_dates: [today, today + 1, today + 2], past_failed_dates: [], future_failed_dates: [today])
    end
    expect(UpdateRankingsJob).to have_received(:perform_later).once.with(season.id, sync_schedule_date: today)
    perform_enqueued_jobs(only: UpdateRankingsJob)
    expect(calculator).not_to have_received(:call)
    expect(GenerateNightlyPredictionsJob).not_to have_received(:perform_later)
    expect(enqueued_jobs).to be_empty
  end
end
