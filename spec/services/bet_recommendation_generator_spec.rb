# frozen_string_literal: true

require 'rails_helper'

describe BetRecommendationGenerator do
  let(:season) { create(:season, :current, average_efficiency: 100.0, average_pace: 70.0) }
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
           home_offensive_efficiency: 107.143,
           away_offensive_efficiency: 100.0,
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
    it 'retains evaluated spread and total sides when their EV is below the recommendation threshold' do
      allow(prediction).to receive_messages(margin_std_deviation: 100.0, total_std_deviation: 100.0)

      recs = described_class.call(game:).compact.index_by(&:bet_type)

      expect(recs.fetch('spread')).to have_attributes(team: 'home', recommended: false)
      expect(recs.fetch('total')).to have_attributes(team: 'under', recommended: false)
    end

    it 'generates spread and moneyline recommendations with their source associations and model output' do
      recs = described_class.call(game:)
      expect(recs.find { |rec| rec.bet_type == 'spread' }).to have_attributes(
        game:, prediction:, game_odd:, bet_type: 'spread', team: be_in([nil, 'home', 'away']),
        vegas_line: be_in([4.5, -4.5]), vegas_odds: -110, model_value: be_in([5.0, -5.0]),
        confidence: be_between(0.0, 1.0), ev: a_kind_of(Float), recommended: be_in([true, false])
      )
      expect(recs.find { |rec| rec.bet_type == 'moneyline' }).to have_attributes(
        game:, prediction:, game_odd:, bet_type: 'moneyline', team: be_in(%w[home away]),
        vegas_odds: be_in([game_odd.moneyline_home, game_odd.moneyline_away, nil]), model_value: be_between(0.0, 1.0),
        confidence: be_between(0.0, 1.0), ev: a_kind_of(Float), recommended: be_in([true, false])
      )
    end

    {
      'spread' => [{ spread_point: nil }, %w[moneyline total]],
      'moneyline' => [{ moneyline_home: nil, moneyline_away: nil }, %w[spread total]],
      'total' => [{ total_points: nil }, %w[spread moneyline]]
    }.each do |market, (missing_odds, remaining_markets)|
      it "retires a removed #{market} market while preserving other markets and historical rows" do
        original = described_class.call(game:).compact
        game_odd.update!(missing_odds)

        expect { described_class.call(game:) }.not_to change(BetRecommendation, :count)

        expect(original.find { |rec| rec.bet_type == market }.reload).not_to be_current
        expect(game.bet_recommendations.where(current: true).pluck(:bet_type))
          .to match_array(remaining_markets)
      end
    end

    [
      [{ moneyline_home: -1000, moneyline_away: nil }, 'home', -0.34],
      [{ moneyline_home: nil, moneyline_away: -1000 }, 'away', -0.56]
    ].each do |prices, selection, ev|
      it "uses the available #{selection} moneyline even when its EV is negative" do
        game_odd.update!(prices)

        recs = described_class.call(game:).compact

        expect(recs.map(&:bet_type)).to contain_exactly('spread', 'moneyline', 'total')
        expect(recs.find(&:moneyline_bet_type?))
          .to have_attributes(team: selection, vegas_odds: -1000, ev:, recommended: false, current: true)
      end
    end

    it 'retires invalid markets repeatedly while retaining rows and other valid markets' do
      original = described_class.call(game:).compact
      identifiers = original.map(&:id)
      game_odd.update!(spread_home_odds: -1, total_under_odds: 99)

      2.times do
        expect { described_class.call(game:) }.not_to change(BetRecommendation, :count)
        expect(game.bet_recommendations.where(current: true).pluck(:bet_type)).to eq(['moneyline'])
      end
      expect(game.bet_recommendations.order(:id).pluck(:id)).to match_array(identifiers)
      expect(original.reject(&:moneyline_bet_type?).map { |rec| rec.reload.current }).to eq([false, false])
    end

    it 'evaluates a valid moneyline side independently of invalid opponent prices' do
      [0, 1, -1, 99, -99].each do |invalid|
        game_odd.update!(moneyline_home: -101, moneyline_away: invalid)
        home = described_class.call(game:).compact.find(&:moneyline_bet_type?)
        expect(home).to have_attributes(team: 'home', vegas_odds: -101, ev: 0.1941, recommended: true)
        game_odd.update!(moneyline_home: invalid, moneyline_away: -1000)
        away = described_class.call(game:).compact.find(&:moneyline_bet_type?)
        expect(away).to have_attributes(team: 'away', vegas_odds: -1000, ev: -0.56, recommended: false)
      end
    end

    it 'retires a moneyline when neither side has a usable price without replacing or deleting its evidence' do
      original = described_class.call(game:).compact.find(&:moneyline_bet_type?)
      saved_price = original.vegas_odds
      game_odd.update!(moneyline_home: -99, moneyline_away: 99)

      2.times { described_class.call(game:) }

      expect(original.reload).to have_attributes(current: false, vegas_odds: saved_price)
      expect(game.bet_recommendations.where(current: true).pluck(:bet_type)).to contain_exactly('spread', 'total')
      expect(game.bet_recommendations.count).to eq(3)
    end

    it 'does not send nonnumeric or nonfinite prices to EV calculations' do
      [nil, '150', Float::NAN, Float::INFINITY, Complex(100, 1)].each do |invalid|
        allow(game_odd).to receive_messages(moneyline_home: invalid, moneyline_away: invalid,
                                            spread_home_odds: invalid, total_under_odds: invalid)
        expect(described_class.call(game:).compact).to be_empty
      end
    end

    it 'restores the previous current set if saving a remaining valid market fails' do
      described_class.call(game:)
      original = game.bet_recommendations.order(:id).map(&:attributes)
      game_odd.update!(spread_home_odds: -1)
      allow(BetRecommendation).to receive(:find_or_initialize_by).and_wrap_original do |find, **attributes|
        find.call(**attributes).tap { |rec| allow(rec).to receive(:save!).and_raise(ActiveRecord::RecordInvalid) }
      end

      expect { described_class.call(game:) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(game.bet_recommendations.order(:id).map(&:attributes)).to eq(original)
    end

    it 'retains the evaluated spread and total sides below the recommendation threshold' do
      prediction.update!(home_score: 75, away_score: 70)
      game_odd.update!(spread_point: -5, total_points: 145)

      recommendations = described_class.call(game:).compact

      expect(recommendations.find(&:spread_bet_type?)).to have_attributes(team: 'home', recommended: false, ev: -0.0455)
      expect(recommendations.find(&:total_bet_type?)).to have_attributes(team: 'over', recommended: false, ev: -0.0455)
    end

    context 'with deterministic score uncertainty' do
      before do
        make_prediction_deterministic
      end

      [0, -5, 5].each do |spread|
        it "skips the deterministic spread at line #{spread} while producing finite moneyline output" do
          game_odd.update!(spread_point: spread)
          expect(prediction.margin_std_deviation).to eq(0)
          recs = described_class.call(game:).compact
          expect(recs.map(&:bet_type)).to eq(['moneyline'])
          expect(recs.first.confidence).to be_finite
          expect(recs.first.ev).to be_finite
          expect(game.bet_recommendations.where(bet_type: 'spread')).to be_empty
        end
      end
    end

    context 'when an existing spread becomes deterministic' do
      let!(:previous_spread) { described_class.call(game:).compact.find { |rec| rec.bet_type == 'spread' } }

      before { make_prediction_deterministic }

      it 'retires the prior current spread while preserving the record and finite moneyline output' do
        previous_confidence = previous_spread.confidence
        recs = described_class.call(game:).compact
        expect(previous_spread.reload).not_to be_current
        expect(previous_spread.confidence).to eq(previous_confidence)
        expect(recs.map(&:bet_type)).to eq(['moneyline'])
        expect(recs.first.confidence).to be_finite
        expect(recs.first).to be_current
      end

      it 'does not retire a current recommendation when evaluating an inactive model' do
        ratings_config_version.update!(current: false)
        described_class.call(game:)
        expect(previous_spread.reload).to be_current
      end

      it 'leaves another games current spread unchanged' do
        other_game = create(:game, season:, start_time: game.start_time + 1.day)
        other_prediction = create(:prediction, game: other_game, home_team_snapshot: home_snapshot,
                                               away_team_snapshot: away_snapshot, ratings_config_version:)
        other_odd = create(:game_odd, game: other_game, fetched_at: Time.zone.now)
        other_spread = create(:bet_recommendation, game: other_game, prediction: other_prediction,
                                                   game_odd: other_odd, ratings_config_version:, current: true)
        described_class.call(game:)
        expect(previous_spread.reload).not_to be_current
        expect(other_spread.reload).to be_current
      end
    end

    context 'when total points are present' do
      before do
        game_odd.update!(total_points: 145.5, total_over_odds: -110, total_under_odds: -110)
        allow(prediction).to receive(:total_std_deviation).and_return(10.0)
      end

      it 'generates a total recommendation with its source associations, line and model output' do
        recs = described_class.call(game:)
        expect(recs.find { |rec| rec.bet_type == 'total' }).to have_attributes(
          game:, prediction:, game_odd:, bet_type: 'total', team: be_in([nil, 'over', 'under']),
          vegas_line: 145.5, vegas_odds: -110, model_value: 145.0,
          confidence: be_between(0.0, 1.0), ev: a_kind_of(Float), recommended: be_in([true, false])
        )
      end
    end
  end

  def make_prediction_deterministic
    [home_snapshot, away_snapshot].each do |snapshot|
      snapshot.update!(offensive_efficiency_volatility: 0, defensive_efficiency_volatility: 0, pace_volatility: 0)
    end
    prediction.reload.update!(home_score: 70, away_score: 70, home_offensive_efficiency: 100,
                              away_offensive_efficiency: 100, home_win_probability: 0.5)
  end
end
