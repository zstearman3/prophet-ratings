# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::ScheduleRefreshExecution do
  let(:first) { Date.new(2025, 11, 1) }
  let(:season) { create(:season, year: 2026, start_date: first, end_date: first + 20.days) }
  let(:attributes) do
    { season:, requested_by: create(:user, :admin), provider: 'sports_reference', mode: 'historical',
      start_date: first, end_date: first + 1.day }
  end
  let(:run) { ScheduleRefreshRun.create!(attributes) }
  let(:service) { instance_double(Ingestion::GamesIngestionService, call: { imported_rows: 0, games: [] }) }

  before do
    allow(Game).to receive(:current_schedule_date).and_return(first + 30.days)
    allow(Ingestion::GamesIngestionService).to receive(:new).and_return(service)
  end

  it 'records historical checkpoints, resumes completed dates, and rescans only when explicitly selected', :aggregate_failures do
    described_class.new(run).call
    expect(run.reload.status).to eq('succeeded')
    expect(GameSyncDate.where(season:, status: 'completed').count).to eq(2)
    repeat = ScheduleRefreshRun.create!(attributes)
    described_class.new(repeat).call
    expect(repeat.reload.report.fetch('days').pluck('status')).to eq(%w[skipped skipped])
    expect(service).to have_received(:call).twice
    rescan = ScheduleRefreshRun.create!(attributes.merge(rescan: true))
    described_class.new(rescan).call
    expect(rescan.reload.status).to eq('succeeded')
    expect(GameSyncDate.where(season:).pluck(:attempts)).to eq([2, 2])
    expect(service).to have_received(:call).exactly(4).times
    described_class.new(rescan).call
    expect(service).to have_received(:call).exactly(4).times
  end

  it 'preserves committed progress after interruption and retries only unfinished dates with the saved intent', :aggregate_failures do
    interrupted = Class.new(Interrupt)
    calls = 0
    allow(service).to receive(:call) do
      calls += 1
      raise interrupted if calls == 2

      { imported_rows: 0, games: [] }
    end
    expect { described_class.new(run).call }.to raise_error(interrupted)
    expect(run.reload.pending_dates).to eq([(first + 1.day).iso8601])
    expect(GameSyncDate.find_by!(season:, schedule_date: first)).to be_completed
    described_class.new(run).call
    child = run.create_retry!(attributes[:requested_by])
    expect(child.attributes.values_at('mode', 'rescan')).to eq(['historical', false])
    expect(child.requested_dates).to eq([(first + 1.day).iso8601])
    described_class.new(child).call
    expect(child.reload.status).to eq('succeeded')
    expect(calls).to eq(3)
  end

  it 'rolls back date completion if saving its retained report fails' do
    run
    allow(run).to receive(:checkpoint).and_raise(IOError, 'private report failure')
    allow(Ingestion::HistoricalSyncDay).to receive(:new).and_wrap_original do |original, **arguments|
      original.call(**arguments).tap { |day| allow(day).to receive(:sleep) }
    end
    described_class.new(run).call
    expect(run.reload.status).to eq('failed')
    expect(GameSyncDate.where(season:, status: 'completed')).not_to exist
    expect(run.pending_dates.size).to eq(2)
    expect(run.report.to_json).not_to include('private report failure')
  end

  it 'shares the saved CBBD budget across the range and makes no requests for a fully completed repeat', :aggregate_failures do
    cbbd_attributes = attributes.merge(provider: 'cbbd', max_requests: 2, retries: 0)
    cbbd = ScheduleRefreshRun.create!(cbbd_attributes)
    allow(ENV).to receive(:fetch).and_call_original
    { 'CBBD_API_KEY' => 'synthetic', 'CBBD_CAPTURE_DIRECTORY' => '/tmp/synthetic' }.each do |key, value|
      allow(ENV).to receive(:fetch).with(key, nil).and_return(value)
    end
    adapter = instance_double(Ingestion::Cbbd::Adapter, call: { 'complete' => true, 'observations' => [],
                                                                'acquisition' => { 'complete' => true, 'attempts' => 2 } })
    allow(Ingestion::Cbbd::Adapter).to receive(:new).and_return(adapter)
    described_class.new(cbbd).call
    expect(cbbd.reload.status).to eq('succeeded')
    expect(Ingestion::Cbbd::Adapter).to have_received(:new).with(season: season.year, start_date: first, end_date: first + 1.day,
                                                                 api_key: 'synthetic', capture_directory: '/tmp/synthetic',
                                                                 max_requests: 2, retries: 0)
    repeated = ScheduleRefreshRun.create!(cbbd_attributes)
    described_class.new(repeated).call
    expect(repeated.reload.status).to eq('succeeded')
    expect(repeated.report.fetch('days').pluck('status')).to eq(%w[skipped skipped])
    expect(adapter).to have_received(:call).once
    expect(cbbd.report.to_json).not_to include('synthetic')
  end

  it 'prevents modifying the saved import mode or rescan decision' do
    expect { run.update!(mode: 'upcoming') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    run.reload
    expect { run.update!(rescan: true) }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
