# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ResumeSeasonRatingsJob do
  let(:model_version) { RatingsConfigVersion.default_version }
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
    RatingsConfigVersion.publish!
    allow(Game).to receive(:current_schedule_date).and_return(season.end_date)
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
    allow(ProphetRatings::OverallRatingsCalculator).to receive(:new).with(season,
                                                                          ratings_config_version: model_version).and_return(calculator)
    allow(calculator).to receive(:call) { |as_of:| called_dates << as_of }

    described_class.perform_now(season.id)

    expect(called_dates).to eq([season.start_date + 1.day, season.end_date])
  end

  it 'honors explicit start and end date overrides' do
    called_dates = []
    calculator = instance_double(ProphetRatings::OverallRatingsCalculator)
    allow(ProphetRatings::OverallRatingsCalculator).to receive(:new).with(season,
                                                                          ratings_config_version: model_version).and_return(calculator)
    allow(calculator).to receive(:call) { |as_of:| called_dates << as_of }

    described_class.perform_now(
      season.id,
      start_date: season.start_date,
      end_date: season.start_date + 1.day
    )

    expect(called_dates).to eq([season.start_date, season.start_date + 1.day])
  end

  it 'caps even explicit end dates at today' do
    allow(Game).to receive(:current_schedule_date).and_return(season.start_date + 1.day)
    calculator = instance_double(ProphetRatings::OverallRatingsCalculator, call: true)
    allow(ProphetRatings::OverallRatingsCalculator).to receive(:new).and_return(calculator)
    described_class.perform_now(season.id, end_date: season.end_date)
    expect(calculator).to have_received(:call).with(as_of: season.start_date)
    expect(calculator).to have_received(:call).with(as_of: season.start_date + 1.day)
    expect(calculator).to have_received(:call).twice
  end

  it 'does not generate history or initialize live values before season start' do
    allow(Game).to receive(:current_schedule_date).and_return(season.start_date - 1.day)
    allow(ProphetRatings::OverallRatingsCalculator).to receive(:new)
    allow(ProphetRatings::PreseasonInitializer).to receive(:new)
    described_class.perform_now(season.id, run_preseason: true)
    expect(ProphetRatings::OverallRatingsCalculator).not_to have_received(:new)
    expect(ProphetRatings::PreseasonInitializer).not_to have_received(:new)
  end

  it 'ignores a legacy future snapshot when choosing the resume date' do
    team_season = create(:team_season, season:)
    create(:team_rating_snapshot, season:, team: team_season.team, team_season:, ratings_config_version:,
                                  snapshot_date: season.end_date + 10.days)
    calculator = instance_double(ProphetRatings::OverallRatingsCalculator, call: true)
    allow(ProphetRatings::OverallRatingsCalculator).to receive(:new).and_return(calculator)
    described_class.perform_now(season.id)
    expect(calculator).to have_received(:call).with(as_of: season.start_date)
  end

  it 'preserves existing live values when preseason initialization is requested' do
    team_season = create(:team_season, season:, adj_defensive_efficiency: 99)
    calculator = instance_double(ProphetRatings::OverallRatingsCalculator, call: true)
    allow(ProphetRatings::OverallRatingsCalculator).to receive(:new).and_return(calculator)
    allow(ProphetRatings::PreseasonInitializer).to receive(:new)
    described_class.perform_now(season.id, run_preseason: true)
    expect(ProphetRatings::PreseasonInitializer).not_to have_received(:new)
    expect(team_season.reload.adj_defensive_efficiency).to eq(99)
  end

  it 'keeps completed days and rolls back the failing day for a resumable retry' do
    team_season = create(:team_season, season:)
    calculator = instance_double(ProphetRatings::OverallRatingsCalculator)
    allow(ProphetRatings::OverallRatingsCalculator).to receive(:new).and_return(calculator)
    allow(calculator).to receive(:call) do |as_of:|
      create(:team_rating_snapshot, season:, team_season:, team: team_season.team, ratings_config_version:, snapshot_date: as_of)
      raise 'failed day' if as_of == season.start_date + 1.day
    end
    expect { described_class.new.perform(season.id) }.to raise_error('failed day')
    expect(season.team_rating_snapshots.pluck(:snapshot_date)).to eq([season.start_date])
  end

  it 'initializes preseason ratings when requested and no snapshots exist for the current config' do
    calculator = instance_double(ProphetRatings::OverallRatingsCalculator)
    allow(ProphetRatings::OverallRatingsCalculator).to receive(:new).with(season,
                                                                          ratings_config_version: model_version).and_return(calculator)
    allow(calculator).to receive(:call)

    initializer = instance_double(ProphetRatings::PreseasonInitializer, call: true)
    allow(ProphetRatings::PreseasonInitializer).to receive(:new)
      .with(season, ratings_config_version: ratings_config_version).and_return(initializer)

    described_class.perform_now(season.id, run_preseason: true)

    expect(ProphetRatings::PreseasonInitializer).to have_received(:new).with(season, ratings_config_version: ratings_config_version)
    expect(initializer).to have_received(:call)
  end

  it 'rolls back partial preseason initialization when an explicit job request fails' do
    team_season = create(:team_season, season:)
    initializer = instance_double(ProphetRatings::PreseasonInitializer)
    allow(ProphetRatings::PreseasonInitializer).to receive(:new).and_return(initializer)
    allow(initializer).to receive(:call) do
      team_season.update!(adj_offensive_efficiency: 120)
      raise 'failed preseason'
    end
    expect { described_class.new.perform(season.id, run_preseason: true) }.to raise_error('failed preseason')
    expect(team_season.reload.adj_offensive_efficiency).to be_nil
  end
end
