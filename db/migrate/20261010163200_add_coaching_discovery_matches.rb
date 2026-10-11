# frozen_string_literal: true

class AddCoachingDiscoveryMatches < ActiveRecord::Migration[8.1]
  def change
    add_reference :coaching_changes, :discovery_team, foreign_key: { to_table: :teams }, index: false
    add_reference :coaching_changes, :discovery_previous_team, foreign_key: { to_table: :teams }, index: false
  end
end
