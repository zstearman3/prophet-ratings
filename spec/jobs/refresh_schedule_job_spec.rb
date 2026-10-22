# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RefreshScheduleJob do
  let(:today) { Date.new(2026, 11, 1) }
  let(:season) { create(:season, year: 2027, start_date: today, end_date: today + 20.days) }
  let(:run) do
    ScheduleRefreshRun.create!(season:, requested_by: create(:user, :admin), provider: 'sports_reference',
                               start_date: today.to_s, end_date: (today + 1.day).to_s)
  end

  before { allow(Game).to receive(:current_schedule_date).and_return(today) }

  def interrupted_delivery
    GoodJob::CurrentThread.execution_interrupted = Time.current
    described_class.perform_now(run.id)
  ensure
    GoodJob::CurrentThread.execution_interrupted = nil
  end

  it 'recovers actual GoodJob interrupted deliveries without acquiring and retains the retry set' do
    run.update!(status: 'running', report: { days: [{ date: today.to_s }] })
    allow(Ingestion::GamesIngestionService).to receive(:new)
    interrupted_delivery
    expect(run.reload.status).to eq('incomplete')
    expect(run.pending_dates).to eq([(today + 1.day).to_s])
    expect(run.build_retry(run.requested_by).requested_dates).to eq([(today + 1.day).to_s])
    expect(Ingestion::GamesIngestionService).not_to have_received(:new)
  end

  it 'does not change a live interrupted run on contention or renew queued and terminal interrupted deliveries' do
    run.update!(status: 'running')
    allow(Ingestion::GamesIngestionService).to receive(:new)
    allow(GoodJob::Job).to receive(:advisory_lock_key).and_return(false)
    expect { interrupted_delivery }.not_to(change { run.reload.attributes })
    allow(GoodJob::Job).to receive(:advisory_lock_key).and_call_original
    run.update!(status: 'queued')
    interrupted_delivery
    expect(run.reload.status).to eq('failed')
    expect(run.pending_dates).to eq([today.to_s, (today + 1.day).to_s])
    %w[succeeded incomplete failed].each do |status|
      run.update!(status:)
      expect { interrupted_delivery }.not_to(change { run.reload.attributes })
    end
    expect(Ingestion::GamesIngestionService).not_to have_received(:new)
  end

  it 'leaves a live run unchanged when its execution lock is held elsewhere' do
    run.update!(status: 'running', report: { days: [{ date: today.to_s }] })
    allow(GoodJob::Job).to receive(:advisory_lock_key).with("prophet-ratings:schedule-refresh:#{run.id}").and_return(false)
    expect { described_class.perform_now(run.id) }.not_to(change { run.reload.attributes })
  end

  it 'reloads state only after acquiring the full execution lock' do
    run
    allow(GoodJob::Job).to receive(:advisory_lock_key) do |*, &block|
      run.update!(status: 'succeeded')
      block.call
    end
    described_class.perform_now(run.id)
    expect(run.reload.status).to eq('succeeded')
  end
end
