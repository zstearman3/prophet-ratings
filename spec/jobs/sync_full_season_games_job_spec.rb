# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SyncFullSeasonGamesJob do
  let(:service) { instance_double(Ingestion::GamesIngestionService, call: { imported_rows: 0 }) }
  let(:today) { Date.current }
  let(:season) do
    create(
      :season,
      year: 2099,
      start_date: today - 5.days,
      end_date: today - 1.day
    )
  end

  before do
    allow(Game).to receive(:current_schedule_date).and_return(Date.current)
    allow(Ingestion::GamesIngestionService).to receive(:new).and_return(service)
  end

  it 'resumes from the latest imported game date when resume is enabled' do
    latest_imported_date = season.start_date + 3.days
    create(:game, season:, start_time: latest_imported_date + 12.hours, home_team_name: 'H1', away_team_name: 'A1')

    called_dates = []
    allow(Ingestion::GamesIngestionService).to receive(:new) do |date:|
      called_dates << date
      service
    end

    described_class.perform_now(season, resume: true)

    expect(called_dates).to eq((latest_imported_date..season.end_date).to_a)
  end

  it 'honors explicit date window overrides' do
    called_dates = []
    allow(Ingestion::GamesIngestionService).to receive(:new) do |date:|
      called_dates << date
      service
    end

    described_class.perform_now(
      season,
      start_date: season.start_date + 1.day,
      end_date: season.start_date + 2.days,
      resume: true
    )

    expect(called_dates).to eq([(season.start_date + 1.day), (season.start_date + 2.days)])
  end

  it 'skips syncing when computed range is empty' do
    described_class.perform_now(
      season,
      start_date: season.end_date + 1.day,
      end_date: season.end_date
    )

    expect(Ingestion::GamesIngestionService).not_to have_received(:new)
  end

  it 'enqueues duplicate repair after syncing when dedupe is enabled' do
    allow(RepairDuplicateGamesJob).to receive(:perform_later)

    described_class.perform_now(season, dedupe: true)

    expect(RepairDuplicateGamesJob).to have_received(:perform_later).with(season_id: season.id, apply: true)
  end

  it 'logs an exhausted date, continues, and lets an explicit recovery revisit that date' do
    first_date = season.start_date
    failed_service = instance_double(Ingestion::GamesIngestionService)
    allow(failed_service).to receive(:call).and_raise('source unavailable')
    allow(Ingestion::GamesIngestionService).to receive(:new) do |date:|
      date == first_date ? failed_service : service
    end
    errors = []
    allow(Rails.logger).to receive(:error) { |&message| errors << message.call }
    job = described_class.new
    allow(job).to receive(:sleep)

    job.perform(season, start_date: first_date, end_date: first_date + 1.day)

    expect(failed_service).to have_received(:call).exactly(6).times
    expect(service).to have_received(:call).once
    expect(errors).to include(/#{first_date}.*source unavailable/)

    allow(Ingestion::GamesIngestionService).to receive(:new).and_return(service)
    job.perform(season, start_date: first_date, end_date: first_date, resume: false)
    expect(Ingestion::GamesIngestionService).to have_received(:new).with(date: first_date).exactly(7).times
    expect(service).to have_received(:call).twice
  end

  it 'does not let a future scheduled game skip historical resume dates' do
    season.update!(end_date: today + 20.days)
    create(:game, season:, start_time: Game.schedule_time_for(today + 10.days), status: :scheduled)
    described_class.perform_now(season, resume: true)
    expect(Ingestion::GamesIngestionService).to have_received(:new).with(date: season.start_date)
    expect(Ingestion::GamesIngestionService).to have_received(:new).with(date: today - 1.day)
  end
end
