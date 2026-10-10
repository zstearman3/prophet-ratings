# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe Ingestion::HistoricalSyncDay do
  let(:season) { create(:season, year: 2026, start_date: Date.new(2025, 11, 1), end_date: Date.new(2025, 11, 3)) }
  let(:service) { instance_double(Ingestion::GamesIngestionService, call: { imported_rows: 0, games: [] }) }

  around do |example|
    original_rake = Rake.application
    original_env = ENV.to_h
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join('lib/tasks/season_bootstrap.rake')
    load Rails.root.join('lib/tasks/import.rake')
    ENV['YEAR'] = '2026'
    %w[SYNC_START_DATE SYNC_END_DATE SYNC_RESUME].each { |key| ENV.delete(key) }
    example.run
  ensure
    Rake.application = original_rake
    ENV.replace(original_env)
  end

  before do
    allow(Ingestion::GamesIngestionService).to receive(:new).and_return(service)
    allow(described_class).to receive(:new).and_wrap_original do |original, **arguments|
      original.call(**arguments).tap { |day| allow(day).to receive(:sleep) }
    end
  end

  def invoke
    Rake::Task['season:sync_games'].reenable
    Rake::Task['season:sync_games'].invoke
  end

  it 'requires an existing explicit YEAR' do
    expect { invoke }.to raise_error(SystemExit, /No season found/)
    create(:season, :current, year: 2026)
    ENV.delete('YEAR')
    expect { invoke }.to raise_error(SystemExit, /YEAR/)
    expect(Ingestion::GamesIngestionService).not_to have_received(:new)
  end

  it 'prints a successful report and resumes only uncompleted dates by default' do
    season
    expect { invoke }.to output(/Games sync complete/).to_stdout
    expect { invoke }.to output(/skipped/).to_stdout
    expect(service).to have_received(:call).exactly(3).times
    expect(Season.current).to be_nil
  end

  it 'exits nonzero with exact recovery dates and does not enqueue an ActiveJob retry' do
    season
    allow(service).to receive(:call).and_raise('HTTP 503')
    allow(SyncFullSeasonGamesJob).to receive(:perform_later)
    expect { invoke }.to raise_error(SystemExit, /retry dates 2025-11-01, 2025-11-02, 2025-11-03/)
      .and output(/"retry_window".*"start_date": "2025-11-01"/m).to_stdout
    expect(SyncFullSeasonGamesJob).not_to have_received(:perform_later)
    expect(GameSyncDate.pluck(:attempts)).to eq([6, 6, 6])
  end

  it 'rejects malformed and out-of-bounds explicit dates before source requests' do
    season
    ENV['SYNC_END_DATE'] = '2025-11-04'
    expect { invoke }.to raise_error(SystemExit, /inside the target season/)
    ENV['SYNC_END_DATE'] = 'not-a-date'
    expect { invoke }.to raise_error(SystemExit, /YYYY-MM-DD/)
    ENV['SYNC_END_DATE'] = '20251103'
    expect { invoke }.to raise_error(SystemExit, /YYYY-MM-DD/)
    expect(Ingestion::GamesIngestionService).not_to have_received(:new)
  end

  it 'supports a bounded explicit rescan after completion' do
    season
    expect { invoke }.to output(/complete/).to_stdout
    ENV['SYNC_RESUME'] = 'false'
    ENV['SYNC_START_DATE'] = '2025-11-02'
    ENV['SYNC_END_DATE'] = '2025-11-02'
    expect { invoke }.to output(/complete/).to_stdout
    expect(GameSyncDate.order(:schedule_date).pluck(:attempts)).to eq([1, 2, 1])
  end

  it 'also fails the legacy all-season synchronous import instead of scheduling retries' do
    season
    allow(service).to receive(:call).and_raise('HTTP 503')
    allow(SyncFullSeasonGamesJob).to receive(:perform_later)
    expect { Rake::Task['import:games'].invoke }.to raise_error(SystemExit, /Historical sync incomplete/)
      .and output(/HTTP 503/).to_stdout
    expect(SyncFullSeasonGamesJob).not_to have_received(:perform_later)
  end
end
