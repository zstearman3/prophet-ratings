# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::GamePredictor do
  describe '#call' do
    let(:season) do
      create(:season,
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

    it 'returns expected prediction structure' do
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

      expect(result[:home_team]).to eq('UConn')
      expect(result[:away_team]).to eq('Houston')
      expect(result[:confidence_level]).to be_in(%w[High Medium Low])
      expect(result[:meta]).to include(:expected_pace, :home_expected_ortg)
    end
  end
end
