# frozen_string_literal: true

# Content identity excludes request provenance, which belongs to immutable observations.
class DepartureSourceCapture < ApplicationRecord
  def readonly?
    persisted?
  end
end
