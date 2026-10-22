# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::ScheduleRefreshExecution do
  let(:today) { Date.new(2026, 11, 1) }
  let(:season) { create(:season, year: 2027, start_date: today, end_date: today + 20.days) }
  let(:run) do
    ScheduleRefreshRun.create!(season:, requested_by: create(:user, :admin), provider: 'sports_reference', start_date: today.to_s,
                               end_date: (today + 1.day).to_s)
  end
  let(:service) { instance_double(Ingestion::GamesIngestionService, call: { imported_rows: 0, games: [] }) }

  before do
    allow(Game).to receive(:current_schedule_date).and_return(today)
    allow(Ingestion::GamesIngestionService).to receive(:new).and_return(service)
  end

  it 'persists empty successful dates and does not reacquire terminal deliveries' do
    described_class.new(run).call
    expect(run.reload.status).to eq('succeeded')
    expect(run.pending_dates).to be_empty
    expect(run.report['days'].size).to eq(2)
    described_class.new(run).call
    expect(service).to have_received(:call).twice
  end

  it 'recovers abandoned running work without renewing acquisition or losing committed dates' do
    run.update!(status: 'running', report: { days: [{ date: today.to_s, imported_rows: 0 }] })
    described_class.new(run).call
    expect(run.reload.status).to eq('incomplete')
    expect(run.pending_dates).to eq([(today + 1.day).to_s])
    expect(service).not_to have_received(:call)
  end

  it 'contains sensitive upstream messages and preserves failed dates' do
    allow(service).to receive(:call).and_raise(StandardError, 'secret-key-example')
    allow(Ingestion::FutureScheduleRefresh).to receive(:new).and_wrap_original do |original, **arguments|
      original.call(**arguments).tap { |refresh| allow(refresh).to receive(:sleep) }
    end
    described_class.new(run).call
    expect(run.reload.status).to eq('incomplete')
    expect(run.report.to_json).not_to include('secret-key-example')
    expect(run.pending_dates.size).to eq(2)
  end

  it 'keeps successful date evidence when the worker dies after its transaction commits' do
    interruption = Class.new(Interrupt)
    calls = 0
    allow(service).to receive(:call) do
      calls += 1
      raise interruption if calls == 2

      { imported_rows: 0, games: [] }
    end
    expect { described_class.new(run).call }.to raise_error(interruption)
    expect(run.reload.status).to eq('running')
    expect(run.pending_dates).to eq([(today + 1.day).to_s])
    described_class.new(run).call
    expect(run.reload.status).to eq('incomplete')
    expect(calls).to eq(2)
  end

  it 'uses the saved CBBD limits after runtime defaults change and acquires only once' do
    cbbd = ScheduleRefreshRun.create!(season:, requested_by: create(:user, :admin), provider: 'cbbd',
                                      start_date: today.to_s, end_date: (today + 1.day).to_s, max_requests: 2, retries: 0)
    allow(ENV).to receive(:fetch).and_call_original
    { 'CBBD_API_KEY' => 'synthetic', 'CBBD_CAPTURE_DIRECTORY' => '/tmp/synthetic',
      'CBBD_MAX_REQUESTS' => '50', 'CBBD_RETRIES' => '3' }.each do |key, value|
      allow(ENV).to receive(:fetch).with(key, nil).and_return(value)
    end
    adapter = instance_double(Ingestion::Cbbd::Adapter, call: { 'complete' => true, 'observations' => [],
                                                                'acquisition' => { 'complete' => true, 'attempts' => 2 } })
    allow(Ingestion::Cbbd::Adapter).to receive(:new).and_return(adapter)
    described_class.new(cbbd).call
    expect(cbbd.reload.status).to eq('succeeded')
    expect(adapter).to have_received(:call).once
    expect(Ingestion::Cbbd::Adapter).to have_received(:new).with(season: season.year, start_date: today, end_date: today + 1.day,
                                                                 api_key: 'synthetic', capture_directory: '/tmp/synthetic',
                                                                 max_requests: 2, retries: 0)
    expect(cbbd.report.to_json).not_to include('synthetic')
  end

  it 'fails aged queued windows before any source call' do
    run
    allow(Game).to receive(:current_schedule_date).and_return(today + 1.day)
    described_class.new(run).call
    expect(run.reload.status).to eq('failed')
    expect(service).not_to have_received(:call)
  end
end
