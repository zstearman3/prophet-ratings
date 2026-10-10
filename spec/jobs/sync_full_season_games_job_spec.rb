# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SyncFullSeasonGamesJob do
  let(:service) { instance_double(Ingestion::GamesIngestionService, call: { imported_rows: 0, games: [] }) }
  let(:today) { Date.new(2026, 2, 21) }
  let(:season) { create(:season, year: 2099, start_date: today - 3.days, end_date: today - 1.day) }
  let(:job) { described_class.new }

  before do
    allow(Game).to receive(:current_schedule_date).and_return(today)
    allow(Ingestion::GamesIngestionService).to receive(:new).and_return(service)
    allow(Ingestion::HistoricalSyncDay).to receive(:new).and_wrap_original do |original, **arguments|
      original.call(**arguments).tap { |day| allow(day).to receive(:sleep) }
    end
  end

  it 'requires an explicit target even with a current season' do
    create(:season, :current)
    expect { job.perform }.to raise_error(ArgumentError)
    expect(Ingestion::GamesIngestionService).not_to have_received(:new)
  end

  it 'does not infer completed dates from historical or future games' do
    season.update!(end_date: today + 10.days)
    create(:game, season:, start_time: Game.schedule_time_for(season.start_date))
    create(:game, season:, start_time: Game.schedule_time_for(today + 5.days))
    result = job.perform(season, resume: true)
    expect(result[:days].pluck(:date)).to eq((season.start_date...today).to_a)
    expect(GameSyncDate.where(status: 'completed').count).to eq(3)
  end

  it 'skips completed empty dates on resume but explicitly rescans with resume false' do
    job.perform(season)
    result = job.perform(season)
    expect(result[:days].pluck(:status)).to eq(%w[skipped skipped skipped])
    expect(service).to have_received(:call).exactly(3).times
    job.perform(season, resume: false)
    expect(GameSyncDate.pluck(:attempts)).to eq([2, 2, 2])
    expect(GameSyncDate.pluck(:imported_rows)).to eq([0, 0, 0])
  end

  it 'honors an explicit inclusive window for a season ID' do
    first = season.start_date + 1.day
    result = job.perform(season.id, start_date: first.iso8601, end_date: season.end_date.iso8601)
    expect(result[:days].pluck(:date)).to eq([first, season.end_date])
    expect(Ingestion::GamesIngestionService).to have_received(:new).with(date: first, season:)
  end

  it 'rejects malformed, reversed, out-of-season and future bounds before ingestion' do
    windows = [
      { start_date: 'garbage' }, { end_date: '2026-02-30' }, { start_date: '' },
      { start_date: '20260218' }, { start_date: today.to_time },
      { start_date: season.start_date - 1.day }, { end_date: season.end_date + 1.day },
      { start_date: season.end_date, end_date: season.start_date }
    ]
    windows.each { |window| expect { job.perform(season, **window) }.to raise_error(ArgumentError) }
    season.update!(end_date: today + 5.days)
    expect { job.perform(season, end_date: today) }.to raise_error(ArgumentError)
    expect(Ingestion::GamesIngestionService).not_to have_received(:new)
  end

  it 'continues after an exhausted middle hole, raises a report, and retries only the hole on resume' do
    middle = season.start_date + 1.day
    failing = instance_double(Ingestion::GamesIngestionService)
    allow(failing).to receive(:call).and_raise('source unavailable')
    allow(Ingestion::GamesIngestionService).to receive(:new) { |date:, **| date == middle ? failing : service }
    expect { job.perform(season) }.to raise_error(described_class::IncompleteSync) do |error|
      expect(error.report).to include(failed_dates: [middle], retry_window: { start_date: middle, end_date: middle, resume: true })
    end
    expect(GameSyncDate.find_by!(schedule_date: middle)).to have_attributes(status: 'failed', attempts: 6,
                                                                            last_error: 'RuntimeError: source unavailable')
    allow(Ingestion::GamesIngestionService).to receive(:new).and_return(service)
    result = job.perform(season)
    expect(result[:days].pluck(:status)).to eq(%w[skipped completed skipped])
    expect(GameSyncDate.find_by!(schedule_date: middle)).to have_attributes(attempts: 7, status: 'completed')
  end

  it 'rolls back partial writes and records failure before an idempotent retry' do
    calls = 0
    allow(service).to receive(:call) do
      calls += 1
      create(:game, season:, start_time: Game.schedule_time_for(season.start_date))
      raise 'second batch failed' if calls == 1

      { imported_rows: 1, games: [] }
    end
    job.perform(season, start_date: season.start_date, end_date: season.start_date)
    expect(season.games.count).to eq(1)
    expect(GameSyncDate.first).to have_attributes(status: 'completed', attempts: 2,
                                                  last_error: 'RuntimeError: second batch failed', imported_rows: 1)
  end

  it 'leaves an interrupted attempt pending and retries it without duplicate writes' do
    allow(service).to receive(:call) do
      create(:game, season:, start_time: Game.schedule_time_for(season.start_date))
      raise Interrupt
    end
    expect { job.perform(season) }.to raise_error(Interrupt)
    expect(GameSyncDate.first).to have_attributes(status: 'pending', attempts: 1, completed_at: nil)
    expect(season.games.count).to eq(0)
    allow(service).to receive(:call).and_return(imported_rows: 0, games: [])
    job.perform(season)
    expect(GameSyncDate.find_by!(schedule_date: season.start_date)).to have_attributes(status: 'completed', attempts: 2)
  end

  it 'does not mark ambiguous reconciliation complete or enqueue dedupe after failures' do
    allow(service).to receive(:call).and_return(imported_rows: 0, games: [{ outcome: 'ambiguous', candidate_ids: [1, 2] }])
    allow(RepairDuplicateGamesJob).to receive(:perform_later)
    expect { job.perform(season, dedupe: true) }.to raise_error(described_class::IncompleteSync)
    expect(GameSyncDate.pluck(:status)).to eq(%w[failed failed failed])
    expect(RepairDuplicateGamesJob).not_to have_received(:perform_later)
  end

  it 'reports overlapping historical dates without touching their checkpoints' do
    date = season.start_date
    connection = PG.connect(ENV.fetch('TEST_DATABASE_URL'))
    connection.exec_params("SELECT pg_advisory_lock(('x'||substr(md5($1::text), 1, 16))::bit(64)::bigint)",
                           ["historical-game-sync:#{season.id}:#{date}"])
    result = Ingestion::HistoricalSyncDay.new(season:, date:, resume: true).call
    expect(result).to include(date:, error: /Another historical sync/)
    expect(Ingestion::GamesIngestionService).not_to have_received(:new)
    expect(GameSyncDate.count).to eq(0)
  ensure
    connection&.close
  end

  it 'defaults to no ratings or duplicate repair and retains explicit dedupe' do
    allow(UpdateRankingsJob).to receive(:perform_later)
    allow(RepairDuplicateGamesJob).to receive(:perform_later)
    job.perform(season)
    expect(UpdateRankingsJob).not_to have_received(:perform_later)
    expect(RepairDuplicateGamesJob).not_to have_received(:perform_later)
    job.perform(season, dedupe: true)
    expect(RepairDuplicateGamesJob).to have_received(:perform_later).with(season_id: season.id, apply: true)
  end
end
