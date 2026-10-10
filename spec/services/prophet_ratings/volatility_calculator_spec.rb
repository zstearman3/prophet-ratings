# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::VolatilityCalculator do
  let(:season) { create(:season, efficiency_std_deviation: 7, pace_std_deviation: 2) }
  let(:version) { create(:ratings_config_version) }
  let(:home) do
    create(:team_rating_snapshot, season:, team_season: create(:team_season, season:), ratings_config_version: version, stats: {})
  end
  let(:away) do
    create(:team_rating_snapshot, season:, team_season: create(:team_season, season:), ratings_config_version: version, stats: {})
  end

  def calculator(**)
    described_class.new(home_rating_snapshot: home, away_rating_snapshot: away, season:, **)
  end

  it 'falls back from absent snapshot deviations to season values then the selected model' do
    expect(calculator.home_offensive_volatility).to eq(7)
    expect(calculator.home_pace_volatility).to eq(2)
    season.efficiency_std_deviation = nil
    season.pace_std_deviation = nil
    expect(calculator.home_offensive_volatility).to eq(11.5)
    expect(calculator.home_pace_volatility).to eq(4.5)
  end

  it 'retains independent additive unequal contributions and applies the modifier once' do
    home.offensive_efficiency_volatility = 6
    away.defensive_efficiency_volatility = 8
    expect(calculator(upset_modifier: 2).total_home_volatility).to eq(20)
    expect(calculator.total_away_volatility).to eq(Math.sqrt(98))
    expect(calculator.total_pace_volatility).to eq(Math.sqrt(8))
  end

  it 'accepts explicit zero deviations without invoking a fallback' do
    home.offensive_efficiency_volatility = 0
    away.defensive_efficiency_volatility = 0
    home.pace_volatility = 0
    away.pace_volatility = 0
    expect(calculator.total_home_volatility).to eq(0)
    expect(calculator.total_pace_volatility).to eq(0)
  end

  [nil, -1, Float::NAN, Float::INFINITY].each do |invalid|
    it "rejects invalid upset modifier #{invalid.inspect}" do
      expect { calculator(upset_modifier: invalid) }.to raise_error(ArgumentError, /volatility/)
    end
  end

  [-1, Float::NAN, Float::INFINITY].each do |invalid|
    it "rejects invalid provided season fallback #{invalid.inspect}" do
      season.efficiency_std_deviation = invalid
      expect { calculator.total_home_volatility }.to raise_error(ArgumentError, /volatility/)
    end
  end
end
