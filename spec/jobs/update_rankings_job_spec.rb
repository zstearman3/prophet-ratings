# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UpdateRankingsJob do
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

  it 'exits without recalculating when another rankings update holds the lock' do
    allow(GoodJob::Job).to receive(:advisory_lock_key).with(described_class::ADVISORY_LOCK_KEY).and_return(false)

    described_class.perform_now(season.id)

    expect(calculator).not_to have_received(:call)
    expect(GenerateNightlyPredictionsJob).not_to have_received(:perform_later)
  end
end
