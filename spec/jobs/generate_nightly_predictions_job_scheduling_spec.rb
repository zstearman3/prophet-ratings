# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GenerateNightlyPredictionsJob do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  let(:season) do
    create(:season, :current, year: 2027, start_date: '2026-11-01', end_date: '2027-04-10',
                              average_efficiency: 100, average_pace: 70)
  end
  let(:version) { create(:ratings_config_version, current: true) }
  let(:game) { create(:game, season:, status: :scheduled, start_time: Time.utc(2026, 11, 2, 23), venue_type: 'neutral') }

  around do |example|
    travel_to Time.utc(2026, 10, 30, 16) do
      previous = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      example.run
    ensure
      ActiveJob::Base.queue_adapter = previous
    end
  end

  before do
    version
    [true, false].each do |home|
      team_season = create(:team_season, season:, ratings_config_version: version)
      create(:team_game, game:, team: team_season.team, team_season:, home:)
      create(:team_rating_snapshot, :with_forecast_inputs, team_season:, ratings_config_version: version,
                                                           snapshot_date: Date.new(2026, 10, 31), adj_pace: 70,
                                                           offensive_efficiency_volatility: 0,
                                                           defensive_efficiency_volatility: 0, pace_volatility: 0)
    end
  end

  %w[empty failed pending].each do |status|
    it "issues a pregame forecast from snapshots while past sync is #{status}, without recalculating ratings" do
      CbbdSyncRun.create!(season:, ratings_config_version: version, schedule_date: Game.current_schedule_date,
                          bucket: Time.current, maximum_requests: 2, retries: 0, past_status: status, future_status: 'failed')
      snapshots = season.team_rating_snapshots.order(:id).map(&:attributes)
      allow(ProphetRatings::OverallRatingsCalculator).to receive(:new).and_raise('Predictions must not recalculate ratings')
      job = described_class.perform_later(season.id)
      ActiveJob::Base.deserialize(job.serialize).perform_now
      prediction = game.predictions.sole
      aggregate_failures do
        expect(prediction).to have_attributes(forecast_kind: 'pregame', ratings_config_version: version,
                                              input_cutoff: Date.new(2026, 10, 31), generated_at: Time.current)
        expect(prediction.home_score.to_f).to eq(70)
        expect(prediction.away_score.to_f).to eq(70)
        expect(season.team_rating_snapshots.order(:id).map(&:attributes)).to eq(snapshots)
        expect(CbbdSyncRun.sole.analytics_status).to eq('pending')
      end
      ActiveJob::Base.deserialize(described_class.perform_later(season.id).serialize).perform_now
      expect(game.predictions.count).to eq(1)
    end
  end

  it 'still skips missing snapshots and snapshots dated on opening day during preseason' do
    season.team_rating_snapshots.find_each { |snapshot| snapshot.update!(snapshot_date: Date.new(2026, 11, 1)) }
    ActiveJob::Base.deserialize(described_class.perform_later(season.id).serialize).perform_now
    expect(game.predictions).to be_empty
    season.team_rating_snapshots.delete_all
    ActiveJob::Base.deserialize(described_class.perform_later(season.id).serialize).perform_now
    expect(game.predictions).to be_empty
  end

  it 'defers through six busy deliveries and forecasts after the real shared lock is released', :aggregate_failures do
    lock_connection = PG.connect(ENV.fetch('TEST_DATABASE_URL'))
    key_sql = GoodJob::Job.send(:advisory_lock_bigint_sql, '$1::text')
    lock_connection.exec_params("SELECT pg_advisory_lock(#{key_sql})", [HeavyJob::LOCK_KEY])
    job = described_class.set(queue: 'default').perform_later(season.id)
    delivery = job.serialize
    arguments = delivery.fetch('arguments')
    enqueued_jobs.clear
    deferrals = []

    6.times do
      attempted_at = Time.current.to_f
      ActiveJob::Base.deserialize(delivery).perform_now
      expect(game.predictions).to be_empty
      delivery = enqueued_jobs.shift
      deferrals << [delivery.fetch(:at) - attempted_at, delivery.fetch('queue_name'), delivery.fetch('job_id')]
      expect(delivery.fetch('arguments')).to eq(arguments)
      expect(enqueued_jobs).to be_empty
      travel 1.minute
    end
    expect(deferrals.uniq).to eq([[60, 'heavy', job.job_id]])
    lock_connection.close
    lock_connection = nil

    ActiveJob::Base.deserialize(delivery).perform_now
    expect(game.predictions.sole).to have_attributes(forecast_kind: 'pregame', ratings_config_version: version)
    expect(enqueued_jobs).to be_empty
  ensure
    lock_connection&.close
  end

  it 'still exhausts genuine prediction errors after five failures despite earlier delivery deferrals' do
    job = described_class.new(season.id)
    job.executions = 12
    job.exception_executions[[StandardError].to_s] = ApplicationJob::MAX_EXECUTIONS - 1
    allow(ProphetRatings::GamePredictionBuilder).to receive(:new).and_raise('synthetic prediction failure')

    expect { job.perform_now }.to raise_error(StandardError, 'synthetic prediction failure')
    expect(enqueued_jobs).to be_empty
  end
end
