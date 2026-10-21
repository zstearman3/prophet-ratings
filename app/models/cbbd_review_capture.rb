# frozen_string_literal: true

# Captured, already-redacted bytes are append-only private evidence.
class CbbdReviewCapture < ApplicationRecord
  belongs_to :cbbd_review_run
  before_update { raise ActiveRecord::ReadOnlyRecord, 'CBBD captures are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'CBBD captures are immutable' }
end
