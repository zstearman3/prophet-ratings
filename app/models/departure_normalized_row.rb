# frozen_string_literal: true

# Immutable original source row, with provider identities for team-scoped reads.
class DepartureNormalizedRow < ApplicationRecord
  belongs_to :departure_source_normalization

  def readonly?
    persisted?
  end
end
