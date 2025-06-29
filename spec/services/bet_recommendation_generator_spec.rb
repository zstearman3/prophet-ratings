# frozen_string_literal: true

require 'rails_helper'

describe BetRecommendationGenerator do
  let(:season) { create(:season, average_efficiency: 100.0, average_pace: 70.0) }
  let(:ratings_config_version) { create(:ratings_config_version, current: true) }
  let(:game) { create(:game, season:, start_time: Time.zone.today) }
  let(:home_team_season) { create(:team_season, season:, offensive_efficiency_std_dev: 5.0, defensive_efficiency_std_dev: 5.0) }
  let(:away_team_season) { create(:team_season, season:, offensive_efficiency_std_dev: 5.0, defensive_efficiency_std_dev: 5.0) }
  let!(:home_snapshot) do
    create(:team_rating_snapshot,
           team_season: home_team_season,
           snapshot_date: game.start_time.to_date,
           ratings_config_version:,
           adj_offensive_efficiency: 110.0,
           adj_defensive_efficiency: 105.0,
           adj_pace: 72.0)
  end
  let!(:away_snapshot) do
    create(:team_rating_snapshot,
           team_season: away_team_season,
           snapshot_date: game.start_time.to_date,
           ratings_config_version:,
           adj_offensive_efficiency: 108.0,
           adj_defensive_efficiency: 107.0,
           adj_pace: 68.0)
  end
  let!(:prediction) do
    create(:prediction,
           game:,
           home_team_snapshot: home_snapshot,
           away_team_snapshot: away_snapshot,
           ratings_config_version:,
           home_score: 75.0,
           away_score: 70.0,
           pace: 70.0)
  end
  let!(:game_odd) do
    create(:game_odd,
           game:,
           spread_point: 4.5,
           spread_home_odds: -110,
           spread_away_odds: -110,
           fetched_at: Time.zone.now)
  end

  before do
    allow(game).to receive_messages(current_prediction: prediction, game_odd:)
  end

  describe '.call' do
    it 'generates a spread recommendation with expected attributes' do
      recs = described_class.call(game:)
      spread_rec = recs.find { |rec| rec.bet_type == 'spread' }
      expect(spread_rec).to be_present
      expect(spread_rec.game).to eq(game)
      expect(spread_rec.prediction).to eq(prediction)
      expect(spread_rec.game_odd).to eq(game_odd)
      expect(spread_rec.bet_type).to eq('spread')
      expect([nil, 'home', 'away']).to include(spread_rec.team)

      expect(spread_rec.vegas_line).to eq(4.5).or eq(-4.5)
      expect(spread_rec.vegas_odds).to eq(-110)
      expect(spread_rec.model_value).to eq(5.0).or eq(-5.0)
      expect(spread_rec.confidence).to be_between(0.0, 1.0)
      expect(spread_rec.ev).to be_a(Float)
      expect([true, false]).to include(spread_rec.recommended)
    end
  end
end
