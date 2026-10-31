# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GenerateNightlyPredictionsJob do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  self.use_transactional_tests = false

  let(:season) { create(:season, :current, year: 2027, start_date: '2026-11-01', end_date: '2027-04-10') }
  let(:version) { create(:ratings_config_version, current: true) }
  let(:game) { create(:game, season:, status: :scheduled, start_time: Time.utc(2026, 11, 2, 23), venue_type: 'neutral') }

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    travel_to(Time.utc(2026, 10, 30, 16)) { example.run }
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  before do
    version
    [true, false].each do |home|
      team_season = create(:team_season, season:, ratings_config_version: version)
      create(:team_game, game:, team: team_season.team, team_season:, home:)
      create(:team_rating_snapshot, :with_forecast_inputs, team_season:, ratings_config_version: version,
                                                           snapshot_date: Date.new(2026, 10, 31))
    end
    create(:game_odd, game:, fetched_at: Time.current, moneyline_home: -110, moneyline_away: -110)
  end

  after do
    Season.destroy_all
    Team.destroy_all
    RatingsConfigVersion.destroy_all
  end

  it 'refreshes recommendations after a scheduled prediction pass without fetching odds', :aggregate_failures do
    expect { described_class.perform_now(season.id) }.to have_enqueued_job(GenerateBetRecommendationsJob)
    GenerateBetRecommendationsJob.perform_now

    expect(game.current_bet_recommendations.sole.prediction).to eq(game.current_prediction)
    first_prediction = game.current_prediction
    game.home_team_game.team_season.team_rating_snapshots.sole.update!(adj_offensive_efficiency: 125)
    expect { described_class.perform_now(season.id) }.to have_enqueued_job(GenerateBetRecommendationsJob)
    GenerateBetRecommendationsJob.perform_now

    expect(game.current_prediction).not_to eq(first_prediction)
    expect(game.current_bet_recommendations.sole.prediction).to eq(game.current_prediction)
    expect(first_prediction.bet_recommendations.sole).not_to be_current
  end

  it 'defers the direct CBBD-style handoff until its enclosing transaction commits' do
    Season.transaction do
      described_class.new.perform(season.id, ratings_config_version_id: version.id)
      expect(game.predictions.count).to eq(1)
      expect(enqueued_jobs).to be_empty
    end

    expect(enqueued_jobs.pluck(:job)).to eq([GenerateBetRecommendationsJob])
  end

  it 'discards the handoff if the enclosing analytics transaction rolls back' do
    Season.transaction do
      described_class.new.perform(season.id, ratings_config_version_id: version.id)
      raise ActiveRecord::Rollback
    end

    expect(game.predictions).to be_empty
    expect(enqueued_jobs).to be_empty
  end

  it 'does not release recommendations when prediction generation fails' do
    allow(ProphetRatings::GamePredictionBuilder).to receive(:new).and_raise('Synthetic prediction failure')

    expect { described_class.new.perform(season.id) }.to raise_error('Synthetic prediction failure')
    expect(enqueued_jobs).to be_empty
  end
end
