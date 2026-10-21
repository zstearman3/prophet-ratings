# frozen_string_literal: true

# Append-only record of an explicit, fingerprint-guarded operator decision.
class IdentityMappingDecision < ApplicationRecord
  validates :request_digest, :comparison_fingerprint, :post_apply_fingerprint, :reviewer, :reason, presence: true
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Identity mapping decisions are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Identity mapping decisions are immutable' }
end
