# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe 'Concurrent schedule refresh retries' do
  self.use_transactional_tests = false

  let(:today) { Date.new(2026, 11, 1) }
  let(:season) { create(:season, year: 2027, start_date: today, end_date: today + 20.days) }
  let(:admin) { create(:user, :admin, password: 'synthetic-password') }
  let(:run) do
    ScheduleRefreshRun.create!(season:, requested_by: admin, provider: 'sports_reference', start_date: today.to_s,
                               end_date: (today + 1.day).to_s, status: 'incomplete')
  end
  let(:ready) { Queue.new }
  let(:start) { Queue.new }
  let(:threads) { [] }

  before do
    allow(Game).to receive(:current_schedule_date).and_return(today)
    ActiveJob::Base.queue_adapter = :test
  end

  after do
    threads.size.times { start << true }
    threads.each { |thread| Timeout.timeout(10) { thread.value } }
  ensure
    ScheduleRefreshRun.where(retry_of_id: run.id).delete_all
    run.destroy!
    season.destroy!
    admin.destroy!
  end

  def signed_in_session
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.post('/users/sign_in', params: { user: { email: admin.email, password: 'synthetic-password' } })
    expect(session.response).to have_http_status(:redirect)
    session
  end

  def wait_for_retry_locks(pids)
    identifiers = pids.map { |pid| Integer(pid) }.join(',')
    Timeout.timeout(10) do
      loop do
        count = ActiveRecord::Base.connection.select_value(
          "SELECT COUNT(*) FROM pg_stat_activity WHERE pid IN (#{identifiers}) AND wait_event_type = 'Lock'"
        )
        break if count == 2

        sleep 0.01
      end
    end
  end

  it 'persists and enqueues one child across concurrent authenticated POSTs on separate database sessions' do
    target = retry_admin_schedule_refresh_run_path(run)
    sessions = Array.new(2) { signed_in_session }
    pids = []
    run.with_lock do
      sessions.each do |session|
        threads << Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            ready << connection.select_value('SELECT pg_backend_pid()')
            start.pop
            session.post(target)
            session.response.status
          end
        end
      end
      pids = Timeout.timeout(10) { Array.new(2) { ready.pop } }
      2.times { start << true }
      wait_for_retry_locks(pids)
    end
    statuses = threads.map { |thread| Timeout.timeout(10) { thread.value } }
    child = ScheduleRefreshRun.find_by!(retry_of_id: run.id)
    jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == RefreshScheduleJob }
    aggregate_failures do
      expect(pids.uniq.size).to eq(2)
      expect(statuses).to contain_exactly(302, 422)
      expect(ScheduleRefreshRun.where(retry_of_id: run.id).count).to eq(1)
      expect(jobs.pluck(:args)).to eq([[child.id]])
    end
  end
end
