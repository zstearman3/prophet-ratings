# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin historical schedule imports' do
  include Devise::Test::IntegrationHelpers

  let(:today) { Date.new(2026, 10, 24) }
  let(:season) { create(:season, year: 2026, start_date: Date.new(2025, 11, 1), end_date: Date.new(2026, 4, 10)) }
  let(:parameters) do
    { season_id: season.id, refresh: { mode: 'historical', provider: 'sports_reference',
                                       start_date: '2025-11-01', end_date: '2025-11-07', rescan: '0' } }
  end

  before do
    allow(Game).to receive(:current_schedule_date).and_return(today)
    ActiveJob::Base.queue_adapter = :test
    sign_in create(:user, :admin)
  end

  it 'defaults completed seasons to a historical week without importing on GET' do
    expect { get admin_schedule_refresh_runs_path(season_id: season.id) }.not_to have_enqueued_job
    expect(response.parsed_body.at_css('select[name="refresh[mode]"] option[selected]')['value']).to eq('historical')
    expect(response.parsed_body.at_css('input[type="checkbox"][name="refresh[rescan]"]')).to be_present
    expect(response.parsed_body.at_css('input[name="refresh[start_date]"]')['value']).to eq('2025-11-01')
    expect(response.parsed_body.at_css('input[name="refresh[end_date]"]')['value']).to eq('2025-11-07')
  end

  it 'queues a retained historical window and an explicit rescan choice' do
    expect { post admin_schedule_refresh_runs_path, params: parameters }.to have_enqueued_job(RefreshScheduleJob)
    run = ScheduleRefreshRun.last
    expect(run.attributes.values_at('mode', 'rescan')).to eq(['historical', false])
    expect(run.requested_dates.size).to eq(7)
    post admin_schedule_refresh_runs_path, params: parameters.deep_merge(refresh: { rescan: '1' })
    expect(ScheduleRefreshRun.last.rescan).to be(true)
  end

  it 'shows resumed dates distinctly from newly imported dates' do
    post admin_schedule_refresh_runs_path, params: parameters
    run = ScheduleRefreshRun.last
    run.update!(status: 'succeeded', report: { days: [{ date: '2025-11-01', status: 'skipped' }] })
    get admin_schedule_refresh_run_path(run)
    expect(response.body).to include('Already imported', 'Completed previously; no new requests.')
  end

  it 'rejects future historical dates and past upcoming dates without queueing' do
    current = create(:season, year: 2027, start_date: today - 2.days, end_date: today + 20.days)
    [{ mode: 'historical', start_date: today.iso8601, end_date: (today + 1.day).iso8601 },
     { mode: 'upcoming', start_date: (today - 1.day).iso8601, end_date: today.iso8601 }].each do |window|
      post admin_schedule_refresh_runs_path, params: parameters.deep_merge(season_id: current.id, refresh: window)
      expect(response).to have_http_status(:unprocessable_content)
    end
    expect(ScheduleRefreshRun.count).to eq(0)
  end
end
