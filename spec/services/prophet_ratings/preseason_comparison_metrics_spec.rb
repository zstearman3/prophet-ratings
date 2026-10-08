# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::PreseasonComparisonMetrics do
  it 'computes independently reasoned errors, Brier score, and bin means including probability one' do
    rows = [
      { margin_error: -4, total_error: 6, probability: 0.75, outcome: 1.0 },
      { margin_error: 2, total_error: -10, probability: 1.0, outcome: 0.0 }
    ]
    result = described_class.new(rows).call
    expect(result).to include(games: 2, margin_mae: 3.0, total_mae: 8.0, brier_score: 0.53125)
    expect(result[:calibration]).to contain_exactly(
      { lower: 0.7, upper: 0.8, games: 1, mean_probability: 0.75, observed_home_win_rate: 1.0 },
      { lower: 0.9, upper: 1.0, games: 1, mean_probability: 1.0, observed_home_win_rate: 0.0 }
    )
  end

  it 'reports absent evidence as nil rather than zero error' do
    expect(described_class.new([]).call).to eq(games: 0, margin_mae: nil, total_mae: nil, brier_score: nil, calibration: [])
  end
end
