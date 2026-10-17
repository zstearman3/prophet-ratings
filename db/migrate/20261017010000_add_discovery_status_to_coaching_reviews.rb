# frozen_string_literal: true

# Job metadata is separate from the operator's readiness decision.
class AddDiscoveryStatusToCoachingReviews < ActiveRecord::Migration[8.1]
  def change
    change_table :coaching_reviews, bulk: true do |table|
      table.string :discovery_status, null: false, default: 'idle'
      table.datetime :discovered_at
      table.text :discovery_error
    end
  end
end
