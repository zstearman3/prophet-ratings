# frozen_string_literal: true

class AddRatingAnchorsToTeamSeasons < ActiveRecord::Migration[8.1]
  def change
    add_column :team_seasons, :rating_anchors, :jsonb, null: false, default: {}
  end
end
