# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GenerateSeasonRatingsJob do
  before do
    RatingsConfigVersion.publish!
    allow(RatingsConfigVersion).to receive(:ensure_current!).and_return(config)
    allow(ProphetRatings::OverallRatingsCalculator).to receive(:new).and_return(calculator)
    allow(Game).to receive(:current_schedule_date).and_return(last)
  end

  let(:season) { create(:season, year: 2026, start_date: Date.new(2025, 11, 1), end_date: Date.new(2026, 4, 1)) }
  let(:config) { create(:ratings_config_version, current: true) }
  let(:calculator) { instance_double(ProphetRatings::OverallRatingsCalculator, call: true) }
  let(:first) { season.start_date }
  let(:last) { first + 1.day }

  def rebuild(start_date: first, end_date: last)
    described_class.new.perform(season.id, rebuild: true, date_range: start_date..end_date)
  end

  it 'requires explicit rebuild consent and dates before deleting anything' do
    expect { described_class.new.perform(season.id) }.to raise_error(ArgumentError, /Destructive rebuild/)
    expect(RatingsConfigVersion).not_to have_received(:ensure_current!)
  end

  it 'rejects a future rebuild or range outside the season before deleting anything' do
    expect { rebuild(end_date: last + 1.day) }.to raise_error(ArgumentError, /future dates/)
    expect { rebuild(start_date: first - 1.day) }.to raise_error(ArgumentError, /within the season/)
    expect(RatingsConfigVersion).not_to have_received(:ensure_current!)
  end

  it 'recalculates only the requested dates and never initializes preseason implicitly' do
    allow(ProphetRatings::PreseasonInitializer).to receive(:new)
    rebuild
    expect(calculator).to have_received(:call).with(as_of: first)
    expect(calculator).to have_received(:call).with(as_of: last)
    expect(calculator).to have_received(:call).twice
    expect(ProphetRatings::PreseasonInitializer).not_to have_received(:new)
  end

  it 'preserves snapshots outside the requested window, other configurations and other seasons' do
    team_season = create(:team_season, season:)
    selected = create_snapshot(team_season, config, first)
    later = create_snapshot(team_season, config, last + 1.day)
    older_config = create(:ratings_config_version)
    older = create_snapshot(team_season, older_config, first)
    other_team_season = create(:team_season, season: create(:season, year: 2025))
    other = create_snapshot(other_team_season, config, first)
    rebuild
    expect(TeamRatingSnapshot.exists?(selected.id)).to be(false)
    expect(TeamRatingSnapshot.where(id: [later.id, older.id, other.id]).count).to eq(3)
  end

  it 'preserves predictions outside the requested window and other configurations' do
    inside = create(:game, season:, status: :scheduled, start_time: Game.schedule_time_for(first) + 12.hours)
    outside = create(:game, season:, status: :scheduled, start_time: Game.schedule_time_for(last + 1.day) + 12.hours)
    selected = create_prediction(inside, config)
    later = create_prediction(outside, config)
    older = create_prediction(inside, create(:ratings_config_version))
    builder = instance_double(ProphetRatings::GamePredictionBuilder, call: true)
    allow(ProphetRatings::GamePredictionBuilder).to receive(:new).and_return(builder)
    rebuild
    expect(Prediction.exists?(selected.id)).to be(false)
    expect(Prediction.where(id: [later.id, older.id]).count).to eq(2)
  end

  it 'rolls back deletions and live rating writes on a partial failure' do
    team_season = create(:team_season, season:, adj_offensive_efficiency: 110)
    snapshot = create_snapshot(team_season, config, first)
    allow(calculator).to receive(:call) do |as_of:|
      team_season.update!(adj_offensive_efficiency: 120)
      raise 'failed second day' if as_of == last
    end
    expect { rebuild }.to raise_error('failed second day')
    expect(TeamRatingSnapshot.exists?(snapshot.id)).to be(true)
    expect(team_season.reload.adj_offensive_efficiency).to eq(110)
  end

  it 'does not process another seasons games on the same date' do
    other_game = create(:game, season: create(:season, year: 2025), start_time: Game.schedule_time_for(first))
    builder = instance_double(ProphetRatings::GamePredictionBuilder, call: true)
    allow(ProphetRatings::GamePredictionBuilder).to receive(:new).and_return(builder)
    rebuild
    expect(ProphetRatings::GamePredictionBuilder).not_to have_received(:new).with(other_game)
  end

  it 'rejects a narrow window whose snapshots support predictions outside the window' do
    team_season = create(:team_season, season:)
    snapshot = create_snapshot(team_season, config, first)
    game = create(:game, season:, start_time: Game.schedule_time_for(last + 1.day))
    prediction = create(:prediction, game:, home_team_snapshot: snapshot, away_team_snapshot: snapshot, ratings_config_version: config)
    expect { rebuild }.to raise_error(ArgumentError, /outside the rebuild scope/)
    expect(TeamRatingSnapshot.exists?(snapshot.id)).to be(true)
    expect(Prediction.exists?(prediction.id)).to be(true)
  end

  def create_prediction(game, ratings_config_version)
    team_season = create(:team_season, season: game.season)
    snapshot = create_snapshot(team_season, ratings_config_version, game.schedule_date)
    create(:prediction, game:, home_team_snapshot: snapshot, away_team_snapshot: snapshot, ratings_config_version:)
  end

  def create_snapshot(team_season, ratings_config_version, date)
    create(:team_rating_snapshot, team_season:, team: team_season.team, season: team_season.season,
                                  ratings_config_version:, snapshot_date: date)
  end
end
