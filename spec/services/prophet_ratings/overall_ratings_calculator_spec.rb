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
end
