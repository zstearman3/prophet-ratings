# frozen_string_literal: true

# Append-only evidence, including observations held for identity/freshness review.
class GameObservation < ApplicationRecord
  belongs_to :game, optional: true
  belongs_to :scoring_review, class_name: 'GameScoringReview', optional: true, inverse_of: :observations
  validates :outcome, presence: true
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Game observations are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Game observations are immutable' }
end
