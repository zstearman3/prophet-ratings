# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScheduledGameSyncJob do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  let(:date) { Date.new(2025, 11, 2) }
  let(:season) { create(:season, :current, year: 2026, start_date: date - 1, end_date: date + 20) }

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  before do
    season
    RatingsConfigVersion.publish!
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('GAME_SYNC_PROVIDER', 'sports_reference').and_return('cbbd')
  end

  it 'pins a run before enqueue and preserves it across midnight and provider changes' do
    travel_to Time.utc(2025, 11, 2, 12) do
      job = described_class.perform_later
      run = CbbdSyncRun.sole
      expect(run.schedule_date).to eq(date)
      expect(job.arguments).to eq(['cbbd', run.id])
      travel 1.day
      allow(ENV).to receive(:fetch).with('GAME_SYNC_PROVIDER', 'sports_reference').and_return('sports_reference')
      restored = ActiveJob::Base.deserialize(job.serialize)
      restored.perform_now
      expect(restored.arguments).to eq(['cbbd', run.id])
      expect(run.reload).to have_attributes(past_status: 'stale', future_status: 'stale')
      expect(CbbdReviewRun.count).to eq(0)
    end
  end

  it 'rolls back the real GoodJob insert and marker together, then recovers once' do
    travel_to Time.utc(2025, 11, 2, 12) do
      described_class.perform_later
      run = CbbdSyncRun.sole
      run.update!(past_status: 'completed')
      previous = CbbdSyncAnalyticsJob.queue_adapter
      CbbdSyncAnalyticsJob.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
      begin
        expect do
          CbbdSyncRun.transaction do
            run.enqueue_analytics
            expect(GoodJob::Job.where(active_job_id: run.analytics_job_id).count).to eq(1)
            raise ActiveRecord::Rollback
          end
        end.not_to change(GoodJob::Job, :count)
        expect(run.reload.analytics_status).to eq('pending')
        run.enqueue_analytics
        identifier = run.reload.analytics_job_id
        run.enqueue_analytics
        expect(GoodJob::Job.where(active_job_id: identifier).count).to eq(1)
        expect(run.analytics_status).to eq('queued')
      ensure
        CbbdSyncAnalyticsJob.queue_adapter = previous
      end
    end
  end

  it 'retains pinned bounds when season dates change after enqueue' do
    travel_to Time.utc(2025, 11, 2, 12) do
      described_class.perform_later
      run = CbbdSyncRun.sole
      season.update!(start_date: date + 1)
      expect(run.reload.past_dates).to eq([Date.new(2025, 11, 1)])
    end
  end

  it 'pins direct execution before heavy contention and preserves that identity on retry' do
    travel_to Time.utc(2025, 11, 2, 12) do
      allow(GoodJob::Job).to receive(:advisory_lock_key).and_call_original
      allow(GoodJob::Job).to receive(:advisory_lock_key).with(HeavyJob::LOCK_KEY).and_return(false)
      described_class.perform_now
      run = CbbdSyncRun.sole
      expect(CbbdReviewRun.count).to eq(0)
      expect(enqueued_jobs.last[:args]).to eq(['cbbd', run.id])
      expect(run.schedule_date).to eq(date)
    end
  end

  it 'coalesces the repeated fall DST hour into one budget and rejects invalid limits before enqueue' do
    travel_to Time.utc(2026, 11, 1, 5, 10) do
      season.update!(year: 2027, start_date: Date.new(2026, 11, 1), end_date: Date.new(2027, 4, 1))
      described_class.perform_later
      identifier = CbbdSyncRun.sole.id
      travel 1.hour
      described_class.perform_later
      expect(CbbdSyncRun.sole.id).to eq(identifier)
      travel 6.hours
      allow(ENV).to receive(:fetch).with('CBBD_SCHEDULED_MAX_REQUESTS', '50').and_return('0')
      expect { described_class.perform_later }.to raise_error(ActiveRecord::RecordInvalid)
      expect(CbbdReviewRun.count).to eq(0)
    end
  end
end
