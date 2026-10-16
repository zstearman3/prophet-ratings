# frozen_string_literal: true

class AddMembershipCorrectionsToSeasons < ActiveRecord::Migration[8.1]
  def change
    add_column :seasons, :membership_corrections, :jsonb, null: false, default: []
  end
end
