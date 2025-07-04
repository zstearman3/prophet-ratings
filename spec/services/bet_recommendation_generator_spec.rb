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
           pace: 70.0,
           home_win_probability: 0.6)
  end
  let!(:game_odd) do
    create(:game_odd,
           game:,
           spread_point: 4.5,
           spread_home_odds: -110,
           spread_away_odds: -110,
           moneyline_home: -120,
           moneyline_away: +100,
           total_points: 145.5,
           total_over_odds: -110,
           total_under_odds: -110,
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

    it 'generates a moneyline recommendation with expected attributes' do
      recs = described_class.call(game:)
      moneyline_rec = recs.find { |rec| rec.bet_type == 'moneyline' }
      expect(moneyline_rec).to be_present
      expect(moneyline_rec.game).to eq(game)
      expect(moneyline_rec.prediction).to eq(prediction)
      expect(moneyline_rec.game_odd).to eq(game_odd)
      expect(moneyline_rec.bet_type).to eq('moneyline')
      expect(%w[home away]).to include(moneyline_rec.team)
      expect([game_odd.moneyline_home, game_odd.moneyline_away, nil]).to include(moneyline_rec.vegas_odds)
      expect(moneyline_rec.model_value).to be_between(0.0, 1.0)
      expect(moneyline_rec.confidence).to be_between(0.0, 1.0)
      expect(moneyline_rec.ev).to be_a(Float)
      expect([true, false]).to include(moneyline_rec.recommended)
    end

    context 'when total points are present' do
      before do
        game_odd.update!(total_points: 145.5, total_over_odds: -110, total_under_odds: -110)
        allow(prediction).to receive(:total_std_deviation).and_return(10.0)
      end

      it 'generates a total recommendation with expected attributes' do
        recs = described_class.call(game:)
        total_rec = recs.find { |rec| rec.bet_type == 'total' }
        expect(total_rec).to be_present
        expect(total_rec.game).to eq(game)
        expect(total_rec.prediction).to eq(prediction)
        expect(total_rec.game_odd).to eq(game_odd)
        expect(total_rec.bet_type).to eq('total')
        expect([nil, 'over', 'under']).to include(total_rec.team)
        expect(total_rec.vegas_line).to eq(145.5)
        expect(total_rec.vegas_odds).to eq(-110)
        expect(total_rec.model_value).to eq(145.0)
        expect(total_rec.confidence).to be_between(0.0, 1.0)
        expect(total_rec.ev).to be_a(Float)
        expect([true, false]).to include(total_rec.recommended)
      end
    end
  end
end
