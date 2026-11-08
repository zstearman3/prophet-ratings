# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BetRecommendationIssue do
  include ActiveSupport::Testing::TimeHelpers

  let!(:fixture) { build_daily_forecast }
  let(:game) { fixture[0] }
  let(:prediction) { fixture[1] }
  let(:odds) { fixture[2] }

  it 'preserves coherent pregame revisions, reuses retries and stops capture at tipoff', :aggregate_failures do
    BetRecommendationGenerator.call(game:)
    first = described_class.last
    original = first.attributes
    expect(first.evidence.dig('markets', 'spread')).to include('team' => 'away', 'vegas_line' => 5.0, 'vegas_odds' => -110)
    expect(first.evidence.dig('markets', 'spread', 'confidence')).to be_between(0.5, 1)
    travel 1.minute do
      expect { BetRecommendationGenerator.call(game:) }.not_to change(described_class, :count)
      odds.update!(spread_away_odds: 150, fetched_at: Time.current)
      expect { BetRecommendationGenerator.call(game:) }.to change(described_class, :count).by(1)
    end
    expect(first.reload.attributes).to eq(original)
    expect(described_class.last.evidence.dig('markets', 'spread', 'vegas_odds')).to eq(150)
    travel_to game.start_time do
      expect { BetRecommendationGenerator.call(game:) }.not_to change(described_class, :count)
    end
    game.update!(status: :final, home_team_score: 70, away_team_score: 80)
    expect { BetRecommendationGenerator.call(game:) }.not_to change(described_class, :count)
    expect(first.reload.attributes).to eq(original)
  end

  it 'uses one quote object even if an importer replaces its values during generation' do
    generator = BetRecommendationGenerator.new(game)
    allow(generator).to receive(:generate_spread_recommendation).and_wrap_original do |generate, *arguments|
      generate.call(*arguments).tap do
        GameOdd.find(odds.id).update!(moneyline_away: -999, total_points: 999)
      end
    end
    generator.call
    markets = described_class.last.evidence.fetch('markets')
    expect(markets.fetch('moneyline')['vegas_odds']).to eq(150)
    expect(markets.fetch('total')['vegas_line']).to eq(140)
  end

  it 'captures missing markets and unusable quote timing rather than retaining an older actionable set', :aggregate_failures do
    BetRecommendationGenerator.call(game:)
    odds.update!(spread_point: nil)
    allow(odds).to receive(:fetched_at).and_return(nil)
    allow(game).to receive(:game_odd).and_return(odds)
    BetRecommendationGenerator.call(game:)
    latest = described_class.last
    expect(latest.evidence.fetch('markets')).to have_key('spread')
    expect(latest.evidence.dig('markets', 'spread')).to be_nil
    expect(latest.odds_fetched_at).to be_nil
    allow(odds).to receive(:fetched_at).and_call_original
    odds.update!(fetched_at: 1.day.from_now)
    expect { BetRecommendationGenerator.call(game:) }.to change(described_class, :count).by(1)
    expect { latest.update!(evidence: {}) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { latest.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'rolls back the entire set on failure and never captures unverified or future forecasts', :aggregate_failures do
    allow(described_class).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
    expect { BetRecommendationGenerator.call(game:) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(BetRecommendation.count).to eq(0)
    allow(described_class).to receive(:create!).and_call_original
    future = prediction.dup
    future.assign_attributes(generated_at: 1.hour.from_now, revision_key: 'future')
    future.save!
    expect { BetRecommendationGenerator.call(game:) }.not_to change(described_class, :count)
    allow(game).to receive(:current_prediction).and_return(prediction)
    allow(prediction).to receive(:forecast_kind).and_return('legacy_unverified')
    expect { BetRecommendationGenerator.call(game:) }.not_to change(described_class, :count)
  end
end
