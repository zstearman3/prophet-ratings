# frozen_string_literal: true

# A sealed exact team input prepared before an operator approves publication.
class DepartureProposal < ApplicationRecord
  belongs_to :departure_validation
  belongs_to :team
end
