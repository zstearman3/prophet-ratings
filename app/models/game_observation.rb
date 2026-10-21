# frozen_string_literal: true

# Append-only evidence, including observations held for identity/freshness review.
class GameObservation < ApplicationRecord
  belongs_to :game, optional: true
  validates :outcome, presence: true
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Game observations are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Game observations are immutable' }
end
