# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::PredictionEvaluator do
  it 'evaluates predictions without loading the optional chart library' do
    evaluator = described_class.new(
      ratings_config_version: create(:ratings_config_version),
      date_range: Date.new(2026, 1, 1)..Date.new(2026, 1, 2)
    )
    allow(evaluator).to receive(:require).and_call_original

    expect(evaluator.call).to include(
      overall_mae: { pace_error_mae: nil, home_off_mae: nil, away_off_mae: nil },
      prediction_accuracy: { total_predictions: 0, correct_predictions: 0, prediction_accuracy: nil }
    )
    expect(evaluator).not_to have_received(:require).with('gruff')
  end
end
