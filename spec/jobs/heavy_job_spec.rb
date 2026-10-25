# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe HeavyJob do
  self.use_transactional_tests = false
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = adapter
  end

  it 'classifies the complete application inventory while leaving odds ordinary' do
    Rails.application.eager_load!
    inventory = Rails.root.glob('app/jobs/*_job.rb').map { |path| path.basename('.rb').to_s.camelize.constantize }
    jobs = inventory - [ApplicationJob, described_class]
    expect(jobs).to include(PreviewPreseasonJob, AcquireCbbdReviewJob, SyncOddsJob)
    jobs.each do |job|
      expect(job.new.queue_name).to eq(job == SyncOddsJob ? 'default' : 'heavy'), job.name
    end
  end

  it 'protects legacy default deliveries and retries on the prefixed heavy queue' do
    stub_const('HeavyProbeJob', Class.new(HeavyJob) { def perform(_id, _identity) = raise('must not execute') })
    freeze_time
    HeavyProbeJob.queue_name_prefix = 'isolated'
    allow(GoodJob::Job).to receive(:advisory_lock_key).with(HeavyJob::LOCK_KEY).and_return(false)
    expect do
      HeavyProbeJob.set(queue: 'default').perform_now(42, 'stored-identity')
    end.to have_enqueued_job(HeavyProbeJob).with(42, 'stored-identity').on_queue('isolated_heavy').at(5.seconds.from_now)
  end

  it 'does not execute a legacy delivery while another connection holds the real lock' do
    stub_const('HeavyProbeJob', Class.new(HeavyJob) do
      def perform
        raise 'must not execute'
      end
    end)
    ready = Queue.new
    release = Queue.new
    thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        GoodJob::Job.advisory_lock_key(HeavyJob::LOCK_KEY) do
          ready << true
          release.pop
        end
      end
    end
    Timeout.timeout(5) { ready.pop }
    expect { HeavyProbeJob.set(queue: 'default').perform_now }.to have_enqueued_job(HeavyProbeJob).on_queue('heavy')
  ensure
    release << true
    thread&.join(5)
  end

  it 'wraps direct nested perform only once and preserves the existing writer lock' do
    stub_const('NestedHeavyProbeJob', Class.new(HeavyJob) { def perform = 'nested' })
    stub_const('HeavyProbeJob', Class.new(HeavyJob) { def perform = NestedHeavyProbeJob.new.perform })
    allow(GoodJob::Job).to receive(:advisory_lock_key).and_call_original
    HeavyProbeJob.perform_now
    expect(GoodJob::Job).to have_received(:advisory_lock_key).with(HeavyJob::LOCK_KEY).once
  end

  it 'cannot discard lock exhaustion through a subclass StandardError handler' do
    stub_const('HeavyProbeJob', Class.new(HeavyJob) do
      discard_on StandardError
      def perform = raise('must not execute')
    end)
    allow(GoodJob::Job).to receive(:advisory_lock_key).and_return(false)
    job = HeavyProbeJob.new
    job.executions = 4
    expect { job.perform_now }.to raise_error(HeavyJob::Contention)
  end

  it 'releases the real global lock when the body raises' do
    stub_const('HeavyProbeJob', Class.new(HeavyJob) do
      rescue_from(StandardError) { |error| raise error }
      def perform = raise('body failed')
    end)
    expect { HeavyProbeJob.perform_now }.to raise_error('body failed')
    expect(GoodJob::Job.advisory_lock_key(HeavyJob::LOCK_KEY) { true }).to be(true)
  end
end
