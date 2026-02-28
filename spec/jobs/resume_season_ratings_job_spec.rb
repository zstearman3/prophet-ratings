# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ResumeSeasonRatingsJob do
  let(:season) do
    create(
      :season,
      year: 2099,
      start_date: Date.new(2098, 11, 1),
      end_date: Date.new(2098, 11, 3)
    )
  end
  let(:ratings_config_version) { create(:ratings_config_version, current: true) }

  before do
    allow(RatingsConfigVersion).to receive(:ensure_current!).and_return(ratings_config_version)
  end

  it 'resumes from latest snapshot date for the current ratings config when no start date is provided' do
    team_season = create(:team_season, season:)
    create(
      :team_rating_snapshot,
      team_season:,
      team: team_season.team,
      season:,
      ratings_config_version:,
      snapshot_date: season.start_date + 1.day
    )

    called_dates = []
    calculator = instance_double(ProphetRatings::OverallRatingsCalculator)
    allow(ProphetRatings::OverallRatingsCalculator).to receive(:new).with(season).and_return(calculator)
    allow(calculator).to receive(:call) { |as_of:| called_dates << as_of }

    described_class.perform_now(season.id)

    expect(called_dates).to eq([season.start_date + 1.day, season.end_date])
  end

  it 'honors explicit start and end date overrides' do
    called_dates = []
    calculator = instance_double(ProphetRatings::OverallRatingsCalculator)
    allow(ProphetRatings::OverallRatingsCalculator).to receive(:new).with(season).and_return(calculator)
    allow(calculator).to receive(:call) { |as_of:| called_dates << as_of }

    described_class.perform_now(
      season.id,
      start_date: season.start_date,
      end_date: season.start_date + 1.day
    )

    expect(called_dates).to eq([season.start_date, season.start_date + 1.day])
  end

  it 'initializes preseason ratings when requested and no snapshots exist for the current config' do
    calculator = instance_double(ProphetRatings::OverallRatingsCalculator)
    allow(ProphetRatings::OverallRatingsCalculator).to receive(:new).with(season).and_return(calculator)
    allow(calculator).to receive(:call)

    initializer = instance_double(ProphetRatings::PreseasonInitializer, call: true)
    allow(ProphetRatings::PreseasonInitializer).to receive(:new).with(season).and_return(initializer)

    described_class.perform_now(season.id, run_preseason: true)

    expect(ProphetRatings::PreseasonInitializer).to have_received(:new).with(season)
    expect(initializer).to have_received(:call)
  end
end
