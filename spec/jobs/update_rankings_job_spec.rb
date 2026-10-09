# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UpdateRankingsJob do
  include ActiveSupport::Testing::TimeHelpers

  # Commit callbacks must be exercised with real commits, outside fixture transactions.
  self.use_transactional_tests = false

  let(:season) do
    create(
      :season,
      :current,
      year: 2099,
      start_date: Date.new(2098, 11, 1),
      end_date: Date.new(2099, 4, 1)
    )
  end
  let(:calculator) { instance_double(ProphetRatings::OverallRatingsCalculator, call: true) }

  before do
    allow(GoodJob::Job).to receive(:advisory_lock_key).with(described_class::ADVISORY_LOCK_KEY).and_wrap_original do |_method, *, &block|
      block.call
    end
    allow(ProphetRatings::OverallRatingsCalculator).to receive(:new).with(season).and_return(calculator)
    allow(GenerateNightlyPredictionsJob).to receive(:perform_later)
  end

  after do
    Season.destroy_all
    Team.destroy_all
    RatingsConfigVersion.destroy_all
  end

  it 'recalculates rankings and enqueues nightly predictions' do
    described_class.perform_now(season.id)

    expect(ProphetRatings::OverallRatingsCalculator).to have_received(:new).with(season)
    expect(calculator).to have_received(:call)
    expect(GenerateNightlyPredictionsJob).to have_received(:perform_later).with(season.id)
    expect(GoodJob::Job).to have_received(:advisory_lock_key).with(described_class::ADVISORY_LOCK_KEY)
  end

  it 'can skip enqueuing nightly predictions' do
    described_class.perform_now(season.id, enqueue_nightly_predictions: false)

    expect(GenerateNightlyPredictionsJob).not_to have_received(:perform_later)
  end

  it 'waits for an enclosing transaction to commit before enqueueing predictions' do
    season
    Season.transaction do
      described_class.new.perform(season.id)
      expect(GenerateNightlyPredictionsJob).not_to have_received(:perform_later)
    end
    expect(GenerateNightlyPredictionsJob).to have_received(:perform_later).with(season.id)
  end

  it 'does not enqueue predictions when the enclosing transaction rolls back' do
    season
    Season.transaction do
      described_class.new.perform(season.id)
      raise ActiveRecord::Rollback
    end
    expect(GenerateNightlyPredictionsJob).not_to have_received(:perform_later)
  end

  it 'propagates publication failures without enqueueing predictions' do
    allow(calculator).to receive(:call).and_raise('publication failed')
    expect { described_class.new.perform(season.id) }.to raise_error('publication failed')
    expect(GenerateNightlyPredictionsJob).not_to have_received(:perform_later)
  end

  it 'fails clearly for an invalid target' do
    expect { described_class.new.perform(-1) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(GenerateNightlyPredictionsJob).not_to have_received(:perform_later)
  end

  it 'keeps the queued season and its end cutoff after another season becomes current' do
    allow(ProphetRatings::OverallRatingsCalculator).to receive(:new).and_call_original
    team_season = create(:team_season, season:)
    queued = described_class.new(season.id, enqueue_nightly_predictions: false).serialize
    season.update!(current: false)
    create(:season, :current, year: 2100)
    travel_to(Time.utc(2100, 10, 1)) { described_class.deserialize(queued).perform_now }
    expect(team_season.team_rating_snapshots.sole.snapshot_date).to eq(season.end_date)
    expect(ProphetRatings::OverallRatingsCalculator).to have_received(:new).with(season)
  end

  it 'exits without recalculating when another rankings update holds the lock' do
    allow(GoodJob::Job).to receive(:advisory_lock_key).with(described_class::ADVISORY_LOCK_KEY).and_return(false)

    described_class.perform_now(season.id)

    expect(calculator).not_to have_received(:call)
    expect(GenerateNightlyPredictionsJob).not_to have_received(:perform_later)
  end
end
