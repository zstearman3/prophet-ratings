# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::EvaluationReport do
  it 'reports bias, RMSE, and sample deviation independently of mean absolute error' do
    summary = described_class.summary([2.0, -4.0])
    expect(summary).to include(observations: 2, mae: 3.0, bias: -1.0)
    expect(summary[:rmse]).to be_within(1e-12).of(Math.sqrt(10))
    expect(summary[:sd]).to be_within(1e-12).of(Math.sqrt(18))
  end

  it 'keeps negative, zero and positive histogram bins ordered' do
    expect(described_class.histogram([4, -2, 0, -2])).to eq(-2.0 => 2, 0.0 => 1, 4.0 => 1)
  end

  it 'excludes unmatched games from both sides of a comparison' do
    row = { probability: 0.75, outcome: 1, margin_error: 2, total_error: 6,
            efficiency_errors: [], pace_errors: [], side_errors: {} }
    comparison = ProphetRatings::PredictionEvaluator.paired_metrics({ 1 => row, 2 => row.merge(margin_error: 999) },
                                                                    { 1 => row.merge(margin_error: 0), 3 => row })
    expect(comparison[:games]).to eq(1)
    expect(comparison[:baseline][:margin_mae]).to eq(2)
    expect(comparison[:candidate][:margin_mae]).to eq(0)
  end
end
