# frozen_string_literal: true

class AddCoachingDiscoveryPresence < ActiveRecord::Migration[8.1]
  def change
    add_column :coaching_changes, :discovery_present, :boolean
  end
end
