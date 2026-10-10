# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ResumeSeasonRatingsJob do
  let(:version) { RatingsConfigVersion.default_version }
  let(:season) { create(:season, start_date: Date.new(2024, 11, 1), end_date: Date.new(2025, 4, 1)) }
  let!(:teams) { create_list(:team_season, 2, season:) }

  before do
    RatingsConfigVersion.publish!
    ProphetRatings::PreseasonInitializer.new(season, ratings_config_version: version).call
    allow(Game).to receive(:current_schedule_date).and_return(season.end_date)
    unless ENV['REAL_REPLAY_SOLVER'] == '1'
      allow(StatisticsUtils).to receive(:solve_least_squares_with_python) do |rows, _targets, **|
        Array.new(rows.first.size, 0.0)
      end
    end
  end

  def replay(first, last = first)
    ResumeSeasonRatingsJob.new.perform(season.id, start_date: first, end_date: last, ratings_config_version_id: version.id)
  end

  def game_on(date, efficiency: 100, possessions: 70)
    game = create(:game, season:, start_time: Game.schedule_time_for(date) + 12.hours, possessions:, minutes: 40,
                         home_team_score: 70, away_team_score: 70, venue_type: 'neutral', venue_confidence: 'confirmed')
    teams.each_with_index do |team_season, index|
      create(:team_game, game:, team_season:, team: team_season.team, home: index.zero?,
                         offensive_efficiency: efficiency, defensive_efficiency: efficiency,
                         field_goals_made: 20, field_goals_attempted: 40, three_pt_made: 5, three_pt_attempted: 10,
                         turnover_rate: 0.1, offensive_rebound_rate: 0.2, free_throw_rate: 0.3)
    end
    game
  end

  def snapshot_values(date)
    season.team_rating_snapshots.where(snapshot_date: date, ratings_config_version: version).order(:team_id)
          .map { |snapshot| snapshot.attributes.except('id', 'created_at', 'updated_at') }
  end

  it 'replays the opening window identically after later live writes and reverse execution order' do
    game = game_on(season.start_date, efficiency: 130)
    game_on(season.start_date + 30, efficiency: 200, possessions: 90)
    replay(season.start_date, season.start_date + 1)
    first = snapshot_values(season.start_date)
    forecast = game.predictions.sole
    expect(forecast.attributes.slice('forecast_kind', 'home_team_snapshot_id', 'input_cutoff',
                                     'home_offensive_efficiency')).to eq(
                                       'forecast_kind' => 'reconstruction', 'home_team_snapshot_id' => nil,
                                       'input_cutoff' => season.start_date - 1, 'home_offensive_efficiency' => 105.5
                                     )
    expect(forecast.calculation_context.dig('snapshots', 0, 'source', 'reconstruction',
                                            'result_cutoff')).to eq((season.start_date - 1).iso8601)

    replay(season.start_date + 30)
    teams.each { |team| team.update!(adj_offensive_efficiency: 125, adj_pace: 99, adj_turnover_rate: 0.9, pace: 99) }
    season.update!(average_efficiency: 999, average_pace: 99, pace_std_deviation: 99)
    replay(season.start_date)
    expect(snapshot_values(season.start_date)).to eq(first)
    expect(game.predictions.count).to eq(1)
    expect(season.team_rating_snapshots.where(snapshot_date: season.start_date - 2).count).to eq(0)
  end

  it 'solves equal neutral observations with independently known zero effects' do
    date = season.start_date + 30
    game_on(date - 2)
    game_on(date - 1)
    replay(date)
    # 25% prior weight at day 30: .25*105.5 + .75*100; pace .25*69.5 + .75*70.
    teams.each do |team|
      expect(team.reload.adj_offensive_efficiency).to eq(101.375)
      expect(team.adj_defensive_efficiency).to eq(101.375)
      expect(team.adj_pace).to eq(69.875)
      expect(team.rating).to eq(0)
    end
  end

  def add_other_model_prediction(game, snapshots)
    other_version = create(:ratings_config_version)
    other_snapshots = snapshots.map do |snapshot|
      create(:team_rating_snapshot, team: snapshot.team, team_season: snapshot.team_season, season:,
                                    ratings_config_version: other_version, snapshot_date: season.start_date - 1)
    end
    create(:prediction, game:, ratings_config_version: other_version, home_team_snapshot: other_snapshots.first,
                        away_team_snapshot: other_snapshots.last, home_offensive_efficiency_error: 999)
  end

  it 'learns from one eligible issuance per game/model and recomputes residuals from frozen means' do
    date = season.start_date + 2
    game = game_on(date)
    game.update!(venue_type: 'home', venue_confidence: 'confirmed')
    snapshots = teams.map { |team| team.team_rating_snapshots.sole }
    context = ProphetRatings::ForecastContext.capture(game, snapshots, version)
    attributes = { game:, ratings_config_version: version, home_team_snapshot: snapshots.first,
                   away_team_snapshot: snapshots.last, calculation_context: context, forecast_kind: 'pregame',
                   forecast_start_time: game.start_time, input_cutoff: season.start_date - 1,
                   home_offensive_efficiency_error: 999, home_defensive_efficiency_error: 999,
                   away_offensive_efficiency: 100, away_defensive_efficiency: 100, pace: 70 }
    create(:prediction, **attributes, generated_at: game.start_time - 2.hours, revision_key: 'first',
                                      home_offensive_efficiency: 120, home_defensive_efficiency: 80)
    create(:prediction, **attributes, generated_at: game.start_time - 1.hour, revision_key: 'latest',
                                      home_offensive_efficiency: 110, home_defensive_efficiency: 90)
    create(:prediction, **attributes, generated_at: game.start_time + 1.hour, revision_key: 'late',
                                      home_offensive_efficiency: 199, home_defensive_efficiency: 1)
    legacy_game = game_on(date - 1)
    create(:prediction, game: legacy_game, ratings_config_version: version, home_team_snapshot: snapshots.first,
                        away_team_snapshot: snapshots.last, home_offensive_efficiency_error: 999)
    add_other_model_prediction(game, snapshots)

    replay(date)
    # Latest mean errors are +10/-10; one sample has weight 1/16, regardless of saved errors.
    expect(teams.first.reload.home_offense_boost).to eq(1.575)
    expect(teams.first.home_defense_boost).to eq(-2.825)
    expect(teams.first.offensive_efficiency_volatility).to eq(11.5)
    replay(date - 1)
    expect(teams.first.reload.home_offense_boost).to eq(2.2)
  end

  it 'rejects missing captured provenance and rolls back earlier restored teams' do
    teams.last.reload.update!(preseason_prior: nil)
    PreseasonPrior.where(team_season: teams.last).delete_all
    teams.first.update!(adj_offensive_efficiency: 125)
    expect { replay(season.start_date) }.to raise_error(ArgumentError, /captured priors/)
    expect(teams.first.reload.adj_offensive_efficiency).to eq(125)
  end

  it 'rolls back prior-day working state and reconstructions on a failed daily publication' do
    game = game_on(season.start_date)
    teams.first.update!(adj_offensive_efficiency: 125)
    allow(ProphetRatings::TeamRatingSnapshotService).to receive(:new).and_raise('snapshot failure')
    expect { replay(season.start_date) }.to raise_error('snapshot failure')
    expect(teams.first.reload.adj_offensive_efficiency).to eq(125)
    expect(game.predictions).to be_empty
  end
end
