# frozen_string_literal: true

# The first acquisition owns provenance even when successors reuse this observation.
class DepartureCaptureObservation < ApplicationRecord
  belongs_to :departure_source_capture
  belongs_to :departure_acquisition

  def readonly?
    persisted?
  end
end
