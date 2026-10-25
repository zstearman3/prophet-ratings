# frozen_string_literal: true

# Immutable original source row, with indexed provider identities for bounded team reads.
class DepartureNormalizedRow < ApplicationRecord
  belongs_to :departure_source_normalization

  def readonly?
    persisted?
  end
end
