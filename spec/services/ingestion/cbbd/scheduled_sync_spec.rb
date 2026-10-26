# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::Cbbd::ScheduledSync do
  include ActiveSupport::Testing::TimeHelpers

  let(:date) { Date.new(2025, 11, 1) }
  let(:season) { create(:season, year: 2026, start_date: date, end_date: date + 20) }
  let(:run) do
    CbbdSyncRun.create!(season:, ratings_config_version: RatingsConfigVersion.resolve,
                        schedule_date: date + 1, bucket: Time.utc(2025, 11, 2, 6), maximum_requests: 2, retries: 0)
  end
  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/ingestion/cbbd/final.json').read) }
  let(:requests) { [] }
  let(:transport) do
    lambda do |uri, _key|
      requests << uri
      rows = if uri.query.include?('2025-11-01')
               fixture.fetch(uri.path == '/games' ? 'games' : 'boxes')
             else
               []
             end
      { status: 200, headers: {}, body: rows.to_json }
    end
  end

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  before do
    allow(Scraper::GamesScraper).to receive(:new).and_raise('CBBD must not invoke Sports Reference')
    RatingsConfigVersion.publish!
    allow(Game).to receive(:current_schedule_date).and_return(date + 1)
    %w[10 20].each do |external_id|
      team = create(:team)
      create(:team_season, team:, season:)
      TeamExternalIdentity.associate!(team:, provider: 'cbbd', external_id:)
    end
  end

  def execute
    Ingestion::Cbbd::ScheduledSync.new(run.reload, api_key: 'synthetic', transport:).call
  end

  def future_transport
    upcoming = fixture['games'].first.deep_dup.merge('id' => 2, 'startDate' => '2025-11-03T23:00:00Z',
                                                     'status' => 'scheduled', 'homePoints' => 0, 'awayPoints' => 0)
    original = transport
    lambda do |uri, key|
      next original.call(uri, key) if uri.query.include?('2025-11-01')

      requests << uri
      { status: 200, headers: {}, body: (uri.path == '/games' ? [upcoming] : []).to_json }
    end
  end

  def fail_after_prediction_writes
    allow(GenerateNightlyPredictionsJob).to receive(:new).and_wrap_original do |original|
      original.call.tap do |job|
        allow(job).to receive(:perform).and_wrap_original do |perform, *args, **kwargs|
          perform.call(*args, **kwargs)
          raise 'synthetic prediction failure after writes'
        end
      end
    end
  end

  it 'retains two finite acquisitions, imports a final, and never reacquires duplicate delivery', :aggregate_failures do
    execute
    expect(run.reload).to have_attributes(past_status: 'completed', future_status: 'completed')
    expect(Game.sole).to have_attributes(home_team_score: 65, away_team_score: 64, status: 'final')
    expect(CbbdReviewRun.find(run.past_acquisition_id).verified_replay['complete']).to be(true)
    expect(requests.size).to eq(4)
    execute
    expect(requests.size).to eq(4)
    expect(Game.count).to eq(1)
  end

  it 'retains captures after a held canonical date and never renews the failed phase budget' do
    TeamExternalIdentity.delete_all
    execute
    expect(run.reload.past_status).to eq('failed')
    expect(Game.count).to eq(0)
    expect(CbbdReviewRun.find(run.past_acquisition_id).verified_replay['complete']).to be(true)
    execute
    expect(requests.size).to eq(4)
  end

  it 'keeps successful past coverage when future requests fail, retaining each budget' do
    original = transport
    failed_future = lambda do |uri, key|
      if uri.query.include?('2025-11-01')
        original.call(uri, key)
      else
        requests << uri
        { status: 503, headers: {}, body: 'synthetic failure' }
      end
    end
    described_class.new(run, api_key: 'synthetic', transport: failed_future).call
    expect(run.reload).to have_attributes(past_status: 'completed', future_status: 'failed')
    run.enqueue_analytics
    expect(run.reload.analytics_status).to eq('queued')
    execute
    expect(requests.size).to eq(4)
  end

  it 'does not reacquire an interrupted persisted acquisition' do
    acquisition = CbbdReviewRun.create!(season:, start_date: date, end_date: date, maximum_requests: 2, retries: 0, status: 'running')
    run.update!(past_acquisition: acquisition)
    execute
    expect(run.reload.past_status).to eq('failed')
    expect(acquisition.reload.failure).to include('interrupted')
    expect(requests.size).to eq(2) # Future has its own finite budget.
  end

  it 'executes persisted ingestion, daily snapshots and predictions while retaining frozen history', :aggregate_failures do
    travel_to Time.utc(2025, 11, 2, 12) do
      described_class.new(run, api_key: 'synthetic', transport: future_transport).call
      expect(run.reload).to have_attributes(past_status: 'completed', future_status: 'completed')
      create(:game, season:, status: :scheduled, start_time: Time.utc(2025, 11, 4, 23),
                    home_team_name: 'Unmapped synthetic home', away_team_name: 'Unmapped synthetic away')
      run.enqueue_analytics
      fail_after_prediction_writes
      expect { CbbdSyncAnalyticsJob.new.perform(run.id) }.to raise_error('synthetic prediction failure after writes')
      expect(run.reload.analytics_status).to eq('ratings_completed')
      expect(Prediction.count).to eq(0)
      snapshots = season.team_rating_snapshots.order(:id).map(&:attributes)
      allow(GenerateNightlyPredictionsJob).to receive(:new).and_call_original
      CbbdSyncAnalyticsJob.perform_now(run.id)
      expect(season.team_rating_snapshots.order(:id).map(&:attributes)).to eq(snapshots)
      expect(run.reload.analytics_status).to eq('completed')
      expect(season.team_rating_snapshots.pluck(:snapshot_date).uniq).to eq([date])
      expect(season.games.scheduled.count).to eq(2) # One lacks rating inputs; completed is processing, not universal coverage.
      prediction = Prediction.sole
      expect(prediction).to have_attributes(ratings_config_version_id: run.ratings_config_version_id, forecast_kind: 'pregame')
      frozen_payload = prediction.attributes
      CbbdSyncAnalyticsJob.perform_now(run.id)
      expect(prediction.reload.attributes).to eq(frozen_payload)
      expect(requests.size).to eq(4)
    end
  end

  it 'resumes a bounded held historical date offline after identity repair without changing persisted IDs or derived values',
     :aggregate_failures do
    mappings = TeamExternalIdentity.where(provider: 'cbbd').pluck(:team_id, :external_id)
    TeamExternalIdentity.delete_all
    execute
    expect(run.reload.past_status).to eq('failed')
    expect([Game.count, TeamGame.count]).to eq([0, 0])
    mappings.each { |team_id, external_id| TeamExternalIdentity.associate!(team: Team.find(team_id), provider: 'cbbd', external_id:) }
    arguments = { season:, dates: [date], provider: 'cbbd', provider_options: { prepared_run: run.past_acquisition.reload }, resume: true }
    resumed = Ingestion::GameSyncRun.new(**arguments).call
    game = Game.sole
    expect(resumed).to include(complete: true, failed_dates: [])
    expect(game).to have_attributes(home_team_score: 65, away_team_score: 64)
    original = [game.attributes, TeamGame.where(game:).order(:id).map(&:attributes)]
    expect(Ingestion::GameSyncRun.new(**arguments).call[:days].sole[:status]).to eq('skipped')
    expect([game.reload.attributes, TeamGame.where(game:).order(:id).map(&:attributes)]).to eq(original)
    expect(requests.size).to eq(4)
  end

  it 'keeps lock contention visible and rolls back partial ratings before a later retry', :aggregate_failures do
    run.update!(past_status: 'completed', analytics_status: 'queued')
    allow(GoodJob::Job).to receive(:advisory_lock_key).and_call_original
    allow(GoodJob::Job).to receive(:advisory_lock_key).with(Season::RATINGS_LOCK_KEY).and_return(false)
    expect { CbbdSyncAnalyticsJob.new.perform(run.id) }.to raise_error(Season::OperationInProgress)
    expect(run.reload.analytics_status).to eq('queued')
    allow(GoodJob::Job).to receive(:advisory_lock_key).and_call_original
    allow(UpdateRankingsJob).to receive(:recalculate).and_wrap_original do |original, *args, **kwargs|
      original.call(*args, **kwargs)
      raise 'synthetic ratings failure after writes'
    end
    expect { CbbdSyncAnalyticsJob.new.perform(run.id) }.to raise_error('synthetic ratings failure after writes')
    expect(season.team_rating_snapshots.count).to eq(0)
    expect(run.reload.analytics_status).to eq('queued')
    allow(UpdateRankingsJob).to receive(:recalculate).and_call_original
    CbbdSyncAnalyticsJob.perform_now(run.id)
    expect(run.reload.analytics_status).to eq('completed')
    expect(requests).to be_empty
  end

  it 'does not create next-day predictions if authorization expires after ratings commit' do
    run.update!(past_status: 'completed', analytics_status: 'queued')
    allow(Game).to receive(:current_schedule_date).and_return(date + 1, date + 1, date + 2)
    CbbdSyncAnalyticsJob.new.perform(run.id)
    expect(run.reload.analytics_status).to eq('stale')
    expect(season.team_rating_snapshots.pluck(:snapshot_date).uniq).to eq([date])
    expect(Prediction.count).to eq(0)
    expect(requests).to be_empty
  end

  it 'exhausts each phase cap without renewing either budget on duplicate delivery' do
    limited = CbbdSyncRun.create!(season:, ratings_config_version: RatingsConfigVersion.default_version,
                                  schedule_date: date + 1, bucket: Time.utc(2025, 11, 2, 18), maximum_requests: 1, retries: 0)
    described_class.new(limited, api_key: 'synthetic', transport:).call
    expect(limited.reload).to have_attributes(past_status: 'failed', future_status: 'failed')
    expect(requests.size).to eq(2)
    described_class.new(limited, api_key: 'synthetic', transport:).call
    expect(requests.size).to eq(2)
    expect(Game.count).to eq(0)
  end
end
