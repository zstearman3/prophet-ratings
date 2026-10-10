# frozen_string_literal: true

class AddCoachingDiscoveryIdentity < ActiveRecord::Migration[8.1]
  def change
    add_column :coaching_changes, :discovery_school, :string
    add_column :coaching_changes, :discovery_coach_name, :string
    add_column :coaching_changes, :discovery_former_coach, :string
    add_index :coaching_changes, %i[effective_year discovery_school], unique: true,
              name: 'unique_coaching_discovery_school', where: 'discovery_school IS NOT NULL'
  end
end
