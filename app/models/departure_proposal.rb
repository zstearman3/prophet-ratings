# frozen_string_literal: true

# The exact per-team input retained by one signed validation.
class DepartureProposal < ApplicationRecord
  belongs_to :departure_validation
  belongs_to :team

  def readonly?
    persisted?
  end
end
