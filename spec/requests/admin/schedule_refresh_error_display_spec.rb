# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Schedule import error display' do
  include Devise::Test::IntegrationHelpers

  let(:date) { Date.new(2025, 11, 1) }
  let(:season) { create(:season, year: 2026, start_date: date, end_date: date + 20.days) }
  let(:admin) { create(:user, :admin) }
  let(:run) do
    ScheduleRefreshRun.create!(season:, requested_by: admin, provider: 'cbbd', mode: 'historical',
                               start_date: date, end_date: date, max_requests: 10, retries: 0)
  end

  before do
    allow(Game).to receive(:current_schedule_date).and_return(date + 30.days)
    sign_in admin
  end

  it 'explains a retained upstream transport failure without claiming an HTTP status' do
    run.update!(status: 'incomplete', report: { acquisition_complete: false,
                                                acquisition: { failure_reasons: ['transport'] },
                                                days: [{ date: date.iso8601, error: 'Source acquisition or reconciliation failed.' }] })
    get admin_schedule_refresh_run_path(run)
    expect(response.body).to include('CBBD retrieval failed', 'Retry unfinished dates later', 'could not be retrieved')
    expect(response.body).not_to include('HTTP 502', 'Teams need matching')
  end

  it 'distinguishes retained successful rows from games still requiring review' do
    run.update!(status: 'incomplete', report: { days: [{ date: date.iso8601, error: 'Incomplete', imported_rows: 3,
                                                         outcomes: { invalid: 1 } }] })
    get admin_schedule_refresh_run_path(run)
    expect(response.body).to include('3 game rows were committed; remaining games need review.', 'Invalid game stats: 1')
    expect(response.body).not_to include('No changes were saved for this date')
  end

  it 'identifies an all-held date as game review rather than a source outage' do
    run.update!(status: 'incomplete', report: { days: [{ date: date.iso8601, error: 'Incomplete', imported_rows: 0,
                                                         outcomes: { invalid: 1 } }] })
    get admin_schedule_refresh_run_path(run)
    expect(response.body).to include('Some games need review. No games were imported for this date.')
    expect(response.body).not_to include('The source could not be retrieved')
  end

  it 'explains rejected rows and shows safe source team names from scoped evidence' do
    observation = GameObservation.create!(provider: 'cbbd', outcome: 'unmatched', normalized_payload: {
                                            season_year: season.year, schedule_date: date.iso8601,
                                            home: { name: 'Duke' }, away: { name: 'Sample College' }
                                          })
    unsafe = GameObservation.create!(provider: 'cbbd', outcome: 'invalid', normalized_payload: {
                                       season_year: season.year, schedule_date: date.iso8601,
                                       home: { name: '<script>unsafe</script>' }, away: { name: 'CBBD_API_KEY=sensitive' }
                                     })
    run.update!(status: 'incomplete', report: { acquisition_complete: true,
                                                days: [{ date: date.iso8601, error: 'Failure', rolled_back: true,
                                                         outcomes: { unmatched: 2, invalid: 1 },
                                                         rejection_observation_ids: [observation.id, unsafe.id] }] })
    get admin_schedule_refresh_run_path(run)
    expect(response.body).to include('No changes were saved for this date', 'Teams need matching: 2', 'Invalid game stats: 1',
                                     'Duke vs. Sample College', "/admin/game_observation/#{observation.id}")
    expect(response.body).not_to include('CBBD retrieval failed', 'CBBD_API_KEY=sensitive', '<script>unsafe</script>')
  end
end
