# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::OverallRatingsCalculator, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  describe 'target season and cutoff' do
    let(:season) { create(:season) }
    let(:calculator) { described_class.new(season) }
    let!(:team_season) { create(:team_season, season:) }

    it 'defaults to the explicit season end with no current season' do
      calculator.call
      expect(team_season.team_rating_snapshots.sole.snapshot_date).to eq(season.end_date)
    end

    it 'caps an explicit date at the target end even when a newer season is current' do
      create(:season, :current, year: season.year + 1)
      calculator.call(as_of: season.end_date + 100.days)
      expect(team_season.team_rating_snapshots.sole.snapshot_date).to eq(season.end_date)
    end

    it 'uses the Eastern date for a UTC timestamp and propagates one date throughout the pipeline' do
      timestamp = Time.utc(season.year, 11, 2, 3, 59)
      expected_date = Date.new(season.year, 11, 1)
      aggregator = instance_double(ProphetRatings::TeamSeasonStatsAggregator, run: true)
      allow(ProphetRatings::TeamSeasonStatsAggregator).to receive(:new).and_return(aggregator)
      calculator.call(as_of: timestamp)
      expect(ProphetRatings::TeamSeasonStatsAggregator).to have_received(:new).with(season:, as_of: expected_date)
      expect(team_season.team_rating_snapshots.sole.snapshot_date).to eq(expected_date)
    end

    it 'changes the default date only at Eastern midnight' do
      travel_to(Time.utc(season.year, 11, 2, 3, 59)) { calculator.call }
      travel_to(Time.utc(season.year, 11, 2, 4, 0)) { calculator.call }
      expect(team_season.team_rating_snapshots.order(:snapshot_date).pluck(:snapshot_date))
        .to eq([Date.new(season.year, 11, 1), Date.new(season.year, 11, 2)])
    end

    it 'fails clearly without a target season' do
      expect { described_class.new }.to raise_error(ArgumentError, /target season/)
    end

    it 'rejects unsaved targets and invalid season boundaries' do
      expect { described_class.new(build(:season)) }.to raise_error(ArgumentError, /target season/)
      season.end_date = season.start_date
      expect { described_class.new(season) }.to raise_error(ArgumentError, %r{start/end dates})
    end

    it 'rejects an invalid cutoff before writing' do
      expect { calculator.call(as_of: 'not-a-date') }.to raise_error(ArgumentError)
      expect(team_season.team_rating_snapshots).to be_empty
    end
  end

  describe 'atomic daily publication' do
    let(:season) { create(:season) }
    let(:as_of) { season.start_date + 30.days }
    let(:calculator) { described_class.new(season) }
    let!(:teams) do
      Array.new(2) { create(:team_season, season:, adj_offensive_efficiency: 120, adj_defensive_efficiency: 90, adj_pace: 60) }
    end

    before do
      2.times do |index|
        game = create(:game, season:, start_time: Game.schedule_time_for(as_of - index.days) + 12.hours,
                             possessions: 70, minutes: 40, home_team_score: 70, away_team_score: 70)
        teams.each_with_index do |team_season, side|
          create(:team_game, game:, team_season:, team: team_season.team, home: side.zero?,
                             offensive_efficiency: 100, defensive_efficiency: 100)
        end
      end
      # Standard specs stub Python; the separate Docker rehearsal exercises the real solver.
      allow(StatisticsUtils).to receive(:solve_least_squares_with_python) { |rows, _targets, _weights| Array.new(rows.first.size, 0.0) }
      calculator.call(as_of: as_of - 1.day)
    end

    def persisted_state
      [season.reload.attributes, teams.map { |team_season| team_season.reload.attributes },
       season.team_rating_snapshots.order(:id).map(&:attributes), RatingsConfigVersion.order(:id).map(&:attributes)]
    end

    def fail_second_snapshot_save
      saves = 0
      allow(TeamRatingSnapshot).to receive(:find_or_initialize_by).and_wrap_original do |finder, **args|
        finder.call(**args).tap do |snapshot|
          allow(snapshot).to receive(:save!).and_wrap_original do |save, *save_args|
            saves += 1
            save.call(*save_args)
            raise 'snapshot failure' if saves == 2
          end
        end
      end
    end

    it 'rolls back aggregation, season baselines and earlier stat writes on a later solver failure' do
      before_state = persisted_state
      allow(StatisticsUtils).to receive(:solve_least_squares_with_python).and_return([5.0, -5.0, 0.0, 0.0])
      allow(ProphetRatings::AdjustedStatCalculator).to receive(:new).and_wrap_original do |original, **args|
        raise 'mid-solver failure' if args[:raw_stat] == :possessions

        original.call(**args)
      end
      expect { calculator.call(as_of:) }.to raise_error('mid-solver failure')
      expect(persisted_state).to eq(before_state)
    end

    it 'restores live writes and existing snapshots even when the caller rescues inside an outer transaction' do
      teams.first.update!(rating: 999, overall_rank: 99)
      season.update!(average_efficiency: 123)
      before_state = persisted_state
      fail_second_snapshot_save
      Season.transaction do
        expect { calculator.call(as_of: as_of - 1.day) }.to raise_error('snapshot failure')
        expect(persisted_state).to eq(before_state)
        season.update!(name: 'Caller work survives')
      end
      expect(season.reload.name).to eq('Caller work survives')
    end

    it 'leaves no partial new date after a snapshot failure and succeeds on retry without duplicates' do
      before_state = persisted_state
      fail_second_snapshot_save
      expect { calculator.call(as_of:) }.to raise_error('snapshot failure')
      expect(persisted_state).to eq(before_state)
      calculator.call(as_of:)
      calculator.call(as_of:)
      expect(season.team_rating_snapshots.where(snapshot_date: as_of).count).to eq(2)
      expect(teams.map { |team_season| team_season.reload.rating }).to eq([0, 0])
    end
  end

  describe '#enough_finalized_data_for_adjustments?' do
    let(:season) { create(:season) }
    let(:as_of) { season.start_date + 30.days }
    let(:calculator) { described_class.new(season) }

    it 'returns false (and does not raise) when there are no team games' do
      expect { calculator.send(:enough_finalized_data_for_adjustments?, as_of:) }.not_to raise_error
      expect(calculator.send(:enough_finalized_data_for_adjustments?, as_of:)).to be(false)
    end

    it 'returns true when at least two teams have two finalized games each' do
      team_season_one = create(:team_season, season:)
      team_season_two = create(:team_season, season:)

      2.times do |i|
        game_one = create(:game, season:, status: :final, start_time: season.start_date + (i + 1).days)
        create(:team_game, game: game_one, team_season: team_season_one, team: team_season_one.team, home: i.zero?)

        game_two = create(:game, season:, status: :final, start_time: season.start_date + (i + 3).days)
        create(:team_game, game: game_two, team_season: team_season_two, team: team_season_two.team, home: i.zero?)
      end

      expect(calculator.send(:enough_finalized_data_for_adjustments?, as_of:)).to be(true)
    end
  end

  describe '#recalculate_all_aggregate_ratings' do
    let(:season) { create(:season) }
    let(:calculator) { described_class.new(season) }
    let!(:team_season_without_values) do
      create(
        :team_season,
        season:,
        adj_offensive_efficiency: 101.0,
        adj_defensive_efficiency: 99.0,
        home_offense_boost: nil,
        home_defense_boost: nil,
        offensive_efficiency_volatility: nil,
        defensive_efficiency_volatility: nil
      )
    end

    before do
      create(
        :team_season,
        season:,
        adj_offensive_efficiency: 100.0,
        adj_defensive_efficiency: 100.0,
        home_offense_boost: 1.5,
        home_defense_boost: -1.5,
        offensive_efficiency_volatility: 8.0,
        defensive_efficiency_volatility: 7.0
      )
    end

    it 'fills missing boost and volatility defaults before computing totals' do
      expect { calculator.send(:recalculate_all_aggregate_ratings) }.not_to raise_error

      team_season_without_values.reload
      expect(
        [
          team_season_without_values.home_offense_boost,
          team_season_without_values.home_defense_boost,
          team_season_without_values.offensive_efficiency_volatility,
          team_season_without_values.defensive_efficiency_volatility,
          team_season_without_values.total_home_boost,
          team_season_without_values.total_volatility
        ]
      ).to all(be_present)
    end
  end

  describe 'early-season publication' do
    let(:season) { create(:season) }
    let(:calculator) { described_class.new(season) }

    it 'publishes required ranks/defaults when there are no games before the solver gate' do
      team_season = create(:team_season, season:, preseason_adj_offensive_efficiency: 120,
                                         preseason_adj_defensive_efficiency: 100, preseason_adj_pace: 70)
      calculator.call(as_of: season.start_date)
      expect([team_season.reload.rating, team_season.overall_rank, team_season.adj_pace]).to eq([20, 1, 70])
      expect(team_season.team_rating_snapshots.first.snapshot_date).to eq(season.start_date)
    end

    it 'preserves zero/one-game priors while qualified teams are solved at the requested cutoff' do
      teams = Array.new(4) do
        create(:team_season, season:, adj_offensive_efficiency: 120, adj_defensive_efficiency: 100, adj_pace: 70,
                             preseason_adj_offensive_efficiency: 120, preseason_adj_defensive_efficiency: 100, preseason_adj_pace: 70)
      end
      2.times do |index|
        game = create(:game, season:, start_time: season.start_date + (index + 1).days + 12.hours,
                             possessions: 70, minutes: 40, home_team_score: 80, away_team_score: 70)
        teams.first(2).each_with_index do |team_season, side|
          create(:team_game, game:, team_season:, team: team_season.team, home: side.zero?, offensive_efficiency: 110)
        end
      end
      game = create(:game, season:, start_time: season.start_date + 3.days + 12.hours,
                           home_team_score: 80, away_team_score: 70)
      create(:team_game, game:, team_season: teams[2], team: teams[2].team, home: true, offensive_efficiency: 90)
      # An additional final outside the cutoff must not qualify this team.
      future = create(:game, season:, start_time: season.start_date + 35.days + 12.hours)
      create(:team_game, game: future, team_season: teams[2], team: teams[2].team, home: true)
      allow(StatisticsUtils).to receive(:solve_least_squares_with_python) { |rows, _targets, _weights| Array.new(rows.first.size, 0.0) }
      calculator.call(as_of: season.start_date + 20.days)
      expect(StatisticsUtils).to have_received(:solve_least_squares_with_python).at_least(:once)
      expect(teams.last(2).map do |team_season|
        team_season.reload.attributes.values_at('adj_offensive_efficiency', 'adj_defensive_efficiency', 'adj_pace', 'rating')
      end)
        .to eq([[120, 100, 70, 20], [120, 100, 70, 20]])
      # Day 20: 0.5 * 120 + 0.5 * ((110 + 110 + 90) / 3) = 111.667.
      expect(teams.first.reload.adj_offensive_efficiency).to be_within(0.001).of(111.667)
    end
  end
end
