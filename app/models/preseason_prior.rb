# frozen_string_literal: true

# Captured once per team/model. Corrected inputs require a new configuration version.
class PreseasonPrior < ApplicationRecord
  belongs_to :team_season
  belongs_to :ratings_config_version

  validates :inputs, :outputs, presence: true
  validates :team_season_id, uniqueness: { scope: :ratings_config_version_id }

  def readonly?
    persisted?
  end
end
