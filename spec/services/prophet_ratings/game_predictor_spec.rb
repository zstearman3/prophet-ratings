# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::GamePredictor do
  describe '#call' do
    let(:season) do
      create(:season,
             :current,
             average_efficiency: 105.0,
             average_pace: 68.0,
             pace_std_deviation: 3.5,
             efficiency_std_deviation: 6.0)
    end

    let(:home_team) { create(:team, nickname: 'Huskies', school: 'UConn') }
    let(:away_team) { create(:team, nickname: 'Cougars', school: 'Houston') }

    let(:home_team_season) do
      create(:team_season,
             team: home_team,
             season:,
             adj_offensive_efficiency: 112.0,
             adj_defensive_efficiency: 100.0,
             adj_pace: 67.0,
             offensive_efficiency_std_dev: 5.0,
             defensive_efficiency_std_dev: 6.0)
    end

    let(:away_team_season) do
      create(:team_season,
             team: away_team,
             season:,
             adj_offensive_efficiency: 108.0,
             adj_defensive_efficiency: 104.0,
             adj_pace: 69.0,
             offensive_efficiency_std_dev: 7.0,
             defensive_efficiency_std_dev: 8.0)
    end

    it 'includes all expected keys in the prediction structure' do
      config = create(:ratings_config_version)
      home_snapshot = create(:team_rating_snapshot, team_season: home_team_season, ratings_config_version: config)
      away_snapshot = create(:team_rating_snapshot, team_season: away_team_season, ratings_config_version: config)
      result = described_class.new(
        home_rating_snapshot: home_snapshot,
        away_rating_snapshot: away_snapshot,
        season:
      ).call
      expect(result).to include(
        :home_team,
        :away_team,
        :home_expected_score,
        :away_expected_score,
        :expected_margin,
        :win_probability_home,
        :confidence_level,
        :explanation,
        :meta
      )
    end

    it 'assigns correct teams in prediction structure' do
      config = create(:ratings_config_version)
      home_snapshot = create(:team_rating_snapshot, team_season: home_team_season, ratings_config_version: config)
      away_snapshot = create(:team_rating_snapshot, team_season: away_team_season, ratings_config_version: config)
      result = described_class.new(
        home_rating_snapshot: home_snapshot,
        away_rating_snapshot: away_snapshot,
        season:
      ).call
      expect(result[:home_team]).to eq(home_team_season.team.school)
      expect(result[:away_team]).to eq(away_team_season.team.school)
    end

    it 'assigns numeric values for scores and margin' do
      config = create(:ratings_config_version)
      home_snapshot = create(:team_rating_snapshot, team_season: home_team_season, ratings_config_version: config)
      away_snapshot = create(:team_rating_snapshot, team_season: away_team_season, ratings_config_version: config)
      result = described_class.new(
        home_rating_snapshot: home_snapshot,
        away_rating_snapshot: away_snapshot,
        season:
      ).call
      expect(result[:home_expected_score]).to be_a(Numeric)
      expect(result[:away_expected_score]).to be_a(Numeric)
      expect(result[:expected_margin]).to be_a(Numeric)
    end

    it 'assigns probabilities and confidence as floats between 0 and 1' do
      config = create(:ratings_config_version)
      home_snapshot = create(:team_rating_snapshot, team_season: home_team_season, ratings_config_version: config)
      away_snapshot = create(:team_rating_snapshot, team_season: away_team_season, ratings_config_version: config)
      result = described_class.new(
        home_rating_snapshot: home_snapshot,
        away_rating_snapshot: away_snapshot,
        season:
      ).call
      expect(result[:win_probability_home]).to be_between(0.0, 1.0)
      expect(%w[High Medium Low]).to include(result[:confidence_level])
    end

    it 'assigns explanation and meta as correct types' do
      config = create(:ratings_config_version)
      home_snapshot = create(:team_rating_snapshot, team_season: home_team_season, ratings_config_version: config)
      away_snapshot = create(:team_rating_snapshot, team_season: away_team_season, ratings_config_version: config)
      result = described_class.new(
        home_rating_snapshot: home_snapshot,
        away_rating_snapshot: away_snapshot,
        season:
      ).call
      expect(result[:explanation]).to be_a(String)
      expect(result[:meta]).to be_a(Hash)
    end
  end
end
