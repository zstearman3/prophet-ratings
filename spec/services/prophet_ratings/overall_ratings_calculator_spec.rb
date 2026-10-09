# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::OverallRatingsCalculator, type: :service do
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
