# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProphetRatings::GameFinalizer do
  describe '#finalize_prediction!' do
    it 'does not update prediction when error attributes are unavailable' do
      prediction = instance_double(Prediction)
      predictions_relation = instance_double(ActiveRecord::Associations::CollectionProxy)
      game = instance_double(Game, predictions: predictions_relation)
      finalizer = described_class.new(game)

      allow(predictions_relation).to receive(:find_by).and_return(prediction)
      allow(finalizer).to receive_messages(
        home_snapshot: instance_double(TeamRatingSnapshot),
        away_snapshot: instance_double(TeamRatingSnapshot)
      )
      allow(finalizer).to receive(:prediction_error_attributes).with(prediction).and_return(nil)
      allow(prediction).to receive(:update!)

      finalizer.send(:finalize_prediction!)

      expect(prediction).not_to have_received(:update!)
    end
  end
end
