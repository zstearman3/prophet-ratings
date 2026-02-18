# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GenerateSeasonRatingsJob do
  let(:season) do
    create(
      :season,
      year: 2099,
      start_date: Date.new(2098, 11, 1),
      end_date: Date.new(2098, 11, 1)
    )
  end
  let(:ratings_config_version) { create(:ratings_config_version, current: true) }
  let(:calculator) { instance_double(ProphetRatings::OverallRatingsCalculator, call: true) }
  let(:prediction_builder) { instance_double(ProphetRatings::GamePredictionBuilder, call: true) }

  before do
    create(:game, season:, start_time: season.start_date + 12.hours, status: :scheduled)
    allow(RatingsConfigVersion).to receive(:ensure_current!).and_return(ratings_config_version)
    allow(ProphetRatings::OverallRatingsCalculator).to receive(:new).with(season).and_return(calculator)
    allow(ProphetRatings::GamePredictionBuilder).to receive(:new).and_return(prediction_builder)
    allow(GenerateNightlyPredictionsJob).to receive(:perform_later)
  end

  it 'enqueues nightly prediction generation after ratings are built' do
    described_class.perform_now(season.id, run_preseason: false)

    expect(GenerateNightlyPredictionsJob).to have_received(:perform_later).with(season.id)
  end

  it 'can skip nightly prediction generation' do
    described_class.perform_now(season.id, run_preseason: false, enqueue_nightly_predictions: false)

    expect(GenerateNightlyPredictionsJob).not_to have_received(:perform_later)
  end
end
