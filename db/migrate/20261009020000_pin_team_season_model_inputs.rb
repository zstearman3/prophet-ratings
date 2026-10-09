# frozen_string_literal: true

class PinTeamSeasonModelInputs < ActiveRecord::Migration[8.1]
  def change
    add_reference :team_seasons, :ratings_config_version, foreign_key: true
    add_reference :team_seasons, :preseason_prior, foreign_key: true
  end
end
