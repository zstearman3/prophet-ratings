# frozen_string_literal: true

# Immutable authenticated approval of one exact prepared review document.
class DepartureApproval < ApplicationRecord
  belongs_to :departure_validation
  belongs_to :user, optional: true

  def readonly?
    persisted?
  end
end
