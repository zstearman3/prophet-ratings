# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::PreseasonInitializer do
  before { RatingsConfigVersion.publish! }

  let(:season) { create(:season, average_pace: nil, average_efficiency: nil) }
  let!(:home) { create(:team_season, season:, offensive_efficiency_volatility: nil, defensive_efficiency_volatility: nil) }
  let!(:away) { create(:team_season, season:, offensive_efficiency_volatility: nil, defensive_efficiency_volatility: nil) }
  let(:initializer) { described_class.new(season) }

  def scheduled_game
    game = create(:game, season:, status: :scheduled, start_time: season.start_date.in_time_zone + 12.hours)
    create(:team_game, game:, team_season: home, team: home.team, home: true)
    create(:team_game, game:, team_season: away, team: away.team, home: false)
    game
  end

  it 'publishes defaults, deterministic tied ranks and captured snapshots before opening day' do
    initializer.call
    expect([home.reload.overall_rank, away.reload.overall_rank]).to eq([1, 2])
    expect([home.adj_offensive_efficiency, home.adj_pace, home.total_volatility,
            home.pace_volatility, home.total_home_boost, home.adj_effective_fg_percentage_rank]).to eq([105.5, 69.5, 11.5, 4.5, 4.4, nil])
    expect(TeamRatingSnapshot.count).to eq(2)
    snapshot = home.team_rating_snapshots.first
    expect([snapshot.snapshot_date, snapshot.ratings_config_version, snapshot.overall_rank])
      .to eq([season.start_date - 1, RatingsConfigVersion.find_or_create_by_current_config, 1])
    expect(snapshot.stats.dig('preseason_prior', 'outputs', 'preseason_adj_pace')).to eq(69.5)
  end

  it 'produces a neutral scheduled prediction with independently calculated scores and probability' do
    game = scheduled_game
    initializer.call
    prediction = ProphetRatings::GamePredictionBuilder.new(game).call
    # 105.5 points per 100 possessions * 69.5 possessions = 73.3225 each.
    expect([prediction.home_score, prediction.away_score]).to eq([73.32, 73.32])
    expect(prediction.home_win_probability).to eq(0.5)
    ids = TeamRatingSnapshot.order(:id).pluck(:id)
    initializer.call
    expect(TeamRatingSnapshot.order(:id).pluck(:id)).to eq(ids)
    expect(ProphetRatings::GamePredictionBuilder.new(game).call.id).to eq(prediction.id)
    expect([home.reload.overall_rank, away.reload.overall_rank]).to eq([1, 2])
  end

  it 'uses an explicitly selected published model even when a different bundle has the global current flag' do
    version = RatingsConfigVersion.default_version
    stale = create(:ratings_config_version, current: true)
    game = scheduled_game
    described_class.new(season, ratings_config_version: version).call
    prediction = ProphetRatings::GamePredictionBuilder.new(game, ratings_config_version: version).call
    expect(prediction.ratings_config_version).to eq(version)
    expect(stale.reload).to be_current
  end

  it 'keeps zero-game prediction inputs usable after an opening-day ratings update' do
    game = scheduled_game
    initializer.call
    ProphetRatings::OverallRatingsCalculator.new(season).call(as_of: season.start_date)
    prediction = ProphetRatings::GamePredictionBuilder.new(game.reload).call
    expect([prediction.home_score, prediction.away_score, prediction.home_win_probability]).to eq([73.32, 73.32, 0.5])
    expect(home.reload.overall_rank).to eq(1)
  end

  it 'explicitly skips missing or incomplete prediction inputs' do
    game = scheduled_game
    allow(Rails.logger).to receive(:warn)
    expect(ProphetRatings::GamePredictionBuilder.new(game).call).to be_nil
    initializer.call
    home.team_rating_snapshots.first.update!(adj_pace: nil)
    expect(ProphetRatings::GamePredictionBuilder.new(game).call).to be_nil
    expect(Prediction.count).to eq(0)
    expect(Rails.logger).to have_received(:warn).with(/missing or invalid rating inputs/).twice
  end

  it 'rolls back priors, live values, defaults and snapshots after a partial publication failure' do
    service = instance_double(ProphetRatings::TeamRatingSnapshotService)
    allow(ProphetRatings::TeamRatingSnapshotService).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_raise('failed publication')
    expect { initializer.call }.to raise_error('failed publication')
    expect(home.reload.adj_pace).to be_nil
    expect(season.reload.average_efficiency).to be_nil
    expect(PreseasonPrior.count).to eq(0)
    expect(TeamRatingSnapshot.count).to eq(0)
  end

  it 'rolls back publication even when an outer transaction rescues the failure and then permits a retry' do
    service = instance_double(ProphetRatings::TeamRatingSnapshotService)
    allow(ProphetRatings::TeamRatingSnapshotService).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_raise('failed publication')
    Season.transaction do
      expect { initializer.call }.to raise_error('failed publication')
    end
    expect([home.reload.adj_pace, season.reload.average_efficiency, PreseasonPrior.count, TeamRatingSnapshot.count])
      .to eq([nil, nil, 0, 0])
    allow(ProphetRatings::TeamRatingSnapshotService).to receive(:new).and_call_original
    initializer.call
    expect(TeamRatingSnapshot.count).to eq(2)
  end

  it 'rejects a direct publication call after activation without changing outputs' do
    initializer.call
    season.set_current!
    original = TeamRatingSnapshot.order(:id).map(&:attributes)
    expect { initializer.call }.to raise_error(ArgumentError, /in-season outputs/)
    expect(TeamRatingSnapshot.order(:id).map(&:attributes)).to eq(original)
    expect(season.reload).to be_current
  end

  %i[efficiency pace].each do |baseline|
    it "rejects a repeat that would change the #{baseline} baseline with saved predictions and rolls back new captures" do
      game = scheduled_game
      initializer.call
      prediction = ProphetRatings::GamePredictionBuilder.new(game).call
      original = [season.reload.attributes, prediction.attributes, TeamRatingSnapshot.order(:id).map(&:attributes)]
      new_team = create(:team_season, season:)
      if baseline == :efficiency
        create(:team_offseason_profile, team_season: new_team, manual_adjustment: 3, recruiting_score: nil, returning_minutes_pct: nil)
      else
        previous = create(:season, year: season.year - 1, average_pace: 69.5, average_efficiency: 105.5,
                                   avg_adj_offensive_efficiency: 105.5, avg_adj_defensive_efficiency: 105.5)
        create(:team_season, season: previous, team: new_team.team,
                             adj_offensive_efficiency: 105.5, adj_defensive_efficiency: 105.5, adj_pace: 80.5)
      end
      expect { initializer.call }.to raise_error(ArgumentError, /Saved predictions/)
      expect([season.reload.attributes, prediction.reload.attributes, TeamRatingSnapshot.order(:id).map(&:attributes)]).to eq(original)
      expect(new_team.reload.adj_pace).to be_nil
      expect(PreseasonPrior.count).to eq(2)
    end
  end

  it 'rejects publication after live values change without modifying existing outputs' do
    initializer.call
    home.update!(adj_offensive_efficiency: 120)
    before_snapshots = TeamRatingSnapshot.order(:id).map(&:attributes)
    expect { initializer.call }.to raise_error(ArgumentError, /in-season outputs/)
    expect(home.reload.adj_offensive_efficiency).to eq(120)
    expect(TeamRatingSnapshot.order(:id).map(&:attributes)).to eq(before_snapshots)
  end

  it 'rejects publication after finalized games or later snapshots exist' do
    initializer.call
    ProphetRatings::TeamRatingSnapshotService.new(season:, as_of: season.start_date).call
    expect { initializer.call }.to raise_error(ArgumentError, /in-season outputs/)
    season.team_rating_snapshots.where(snapshot_date: season.start_date).destroy_all
    create(:game, season:, status: :final)
    expect { initializer.call }.to raise_error(ArgumentError, /in-season outputs/)
  end
end
