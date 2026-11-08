# frozen_string_literal: true

# Derived current results; immutable recommendation evidence lives in the saved issue.
class BetSettlement < ApplicationRecord
  belongs_to :game
  belongs_to :ratings_config_version
  belongs_to :prediction, optional: true
  belongs_to :bet_recommendation_issue, optional: true
end
