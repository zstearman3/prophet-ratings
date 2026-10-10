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
    expect(result[:log_loss]).to eq('Infinity')
    expect(result[:calibration]).to contain_exactly(
      { lower: 0.7, upper: 0.8, games: 1, mean_probability: 0.75, observed_home_win_rate: 1.0 },
      { lower: 0.9, upper: 1.0, games: 1, mean_probability: 1.0, observed_home_win_rate: 0.0 }
    )
  end

  it 'reports absent evidence as nil rather than zero error' do
    expect(described_class.new([]).call).to eq(games: 0, margin_mae: nil, total_mae: nil, brier_score: nil, log_loss: nil,
                                               efficiency: { observations: 0, mae: nil },
                                               pace: { observations: 0, mae: nil }, calibration: [])
  end

  it 'reports logarithmic loss and counts only present efficiency/pace outcomes' do
    result = described_class.new([{ margin_error: 0, total_error: 0, probability: 0.75, outcome: 1,
                                    efficiency_errors: [-2, 4], pace_errors: [3] }]).call
    expect(result[:log_loss]).to be_within(0.00001).of(-Math.log(0.75))
    expect(result[:efficiency]).to eq(observations: 2, mae: 3.0)
    expect(result[:pace]).to eq(observations: 1, mae: 3.0)
  end
end
