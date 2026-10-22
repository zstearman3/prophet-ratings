# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin schedule refresh' do
  include Devise::Test::IntegrationHelpers

  let(:today) { Date.new(2026, 11, 1) }
  let(:season) { create(:season, year: 2027, start_date: today, end_date: today + 20.days) }
  let(:values) do
    { season_id: season.id, refresh: { provider: 'sports_reference', start_date: today.to_s, end_date: (today + 2.days).to_s } }
  end

  before do
    allow(Game).to receive(:current_schedule_date).and_return(today)
    ActiveJob::Base.queue_adapter = :test
  end

  it 'requires authentication and admin access on read and write routes' do
    get admin_schedule_refresh_runs_path
    expect(response).to redirect_to(new_user_session_path)
    sign_in create(:user)
    get admin_schedule_refresh_runs_path
    expect(response).to have_http_status(:not_found)
    post admin_schedule_refresh_runs_path, params: values
    expect(response).to have_http_status(:not_found)
    post defer_admin_schedule_refresh_runs_path, params: { season_id: season.id, reason: 'Unavailable' }
    expect(response).to have_http_status(:not_found)
  end

  it 'queues one retained ID-only run and reopens honest evidence' do
    sign_in create(:user, :admin)
    expect { get admin_schedule_refresh_runs_path(season_id: season.id) }.not_to change(ScheduleRefreshRun, :count)
    expect(response.body).to include('inclusive Eastern', 'publication')
    expect { post admin_schedule_refresh_runs_path, params: values }.to have_enqueued_job(RefreshScheduleJob)
    run = ScheduleRefreshRun.last
    expect(response).to redirect_to(admin_schedule_refresh_run_path(run))
    get admin_schedule_refresh_run_path(run)
    expect(response.body).to include('queued', 'Refresh status', 'publication')
  end

  it 'rejects invalid dates and records failed enqueues safely' do
    sign_in create(:user, :admin)
    post admin_schedule_refresh_runs_path, params: values.deep_merge(refresh: { start_date: '2026-11-1' })
    expect(response).to have_http_status(:unprocessable_content)
    expect(ScheduleRefreshRun.count).to eq(0)
    allow(RefreshScheduleJob).to receive(:perform_later).and_return(false)
    post admin_schedule_refresh_runs_path, params: values
    expect(ScheduleRefreshRun.last.status).to eq('failed')
  end

  it 'derives retry scope server-side and rejects live parents and expired dates' do
    user = create(:user, :admin)
    sign_in user
    run = ScheduleRefreshRun.create!(values[:refresh].merge(season:, requested_by: user))
    post retry_admin_schedule_refresh_run_path(run), params: { provider: 'cbbd', dates: [today.to_s] }
    expect(response).to have_http_status(:unprocessable_content)
    expect(ScheduleRefreshRun.count).to eq(1)
    run.update!(status: 'incomplete', report: { days: [{ date: today.to_s }] })
    post retry_admin_schedule_refresh_run_path(run), params: { provider: 'cbbd', season_id: 9999, dates: [today.to_s] }
    child = ScheduleRefreshRun.last
    expect(child.provider).to eq('sports_reference')
    expect(child.requested_dates).to eq([(today + 1.day).to_s, (today + 2.days).to_s])
    expect(child.retry_of).to eq(run)
    expect(run.reload.report['days'].size).to eq(1)
    allow(Game).to receive(:current_schedule_date).and_return(today + 3.days)
    post retry_admin_schedule_refresh_run_path(run)
    expect(response).to have_http_status(:unprocessable_content)
    expect(ScheduleRefreshRun.count).to eq(2)
  end

  it 'keeps the authoritative parent season on live and expired retry errors despite forged season parameters' do
    user = create(:user, :admin)
    sign_in user
    run = ScheduleRefreshRun.create!(values[:refresh].merge(season:, requested_by: user))
    newer = create(:season, year: 2028)
    [{}, { season_id: newer.id }].each do |parameters|
      post retry_admin_schedule_refresh_run_path(run), params: parameters
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Season #{season.year}:", admin_offseason_setup_path(season_id: season.id))
      expect(response.parsed_body.at_css('input[name="season_id"]')['value']).to eq(season.id.to_s)
    end
    run.update!(status: 'incomplete')
    allow(Game).to receive(:current_schedule_date).and_return(today + 4.days)
    post retry_admin_schedule_refresh_run_path(run), params: { season_id: newer.id }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Season #{season.year}:", 'historical sync')
    expect(response.parsed_body.at_css('input[name="season_id"]')['value']).to eq(season.id.to_s)
  end

  it 'reports only existing target-season game links and escapes evidence' do
    user = create(:user, :admin)
    sign_in user
    run = ScheduleRefreshRun.create!(values[:refresh].merge(season:, requested_by: user))
    target = create(:game, season:)
    foreign = create(:game, season: create(:season, year: 2028), home_team_name: 'Other home')
    run.update!(status: 'incomplete', report: { absent_ids: [target.id, foreign.id, 999_999],
                                                days: [{ date: today.to_s,
                                                         games: [{ reason: '<script>unsafe</script>', game_id: foreign.id }] }] })
    get admin_schedule_refresh_run_path(run, season_id: foreign.season_id)
    expect(response.body).to include(game_path(target), 'unsafe')
    expect(response.body).not_to include("href=\"#{game_path(foreign)}\"", '<script>unsafe</script>')
    expect(response.body).to include(admin_offseason_setup_path(season_id: season.id))
  end

  it 'records an explicit reasoned deferral without completing readiness' do
    sign_in create(:user, :admin)
    post defer_admin_schedule_refresh_runs_path, params: { season_id: season.id, reason: '' }
    expect(response).to have_http_status(:unprocessable_content)
    post defer_admin_schedule_refresh_runs_path, params: { season_id: season.id, reason: 'Provider schedule is not published yet' }
    expect(ScheduleDeferral.last.reason).to eq('Provider schedule is not published yet')
    get admin_offseason_setup_path(season_id: season.id)
    expect(response.body).to include('Prediction readiness deferred', 'Provider schedule is not published yet')
  end
end
