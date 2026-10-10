# frozen_string_literal: true

class CreateCoachingReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :coaching_changes do |t|
      t.references :team, foreign_key: true
      t.integer :effective_year, null: false
      t.string :coach_name
      t.string :destination_school
      t.references :previous_team, foreign_key: { to_table: :teams }
      t.string :previous_school
      t.integer :previous_year
      t.string :previous_role
      t.boolean :full_season_head_coach, null: false, default: false
      t.string :status, null: false, default: 'pending'
      t.timestamps
    end
    add_index :coaching_changes, [:team_id, :effective_year], unique: true,
              where: "status = 'confirmed'", name: 'unique_confirmed_coaching_destination'
    add_index :coaching_changes, [:effective_year, :status]
    add_check_constraint :coaching_changes, 'effective_year BETWEEN 1 AND 9999', name: 'coaching_effective_year'
    add_check_constraint :coaching_changes, 'previous_year BETWEEN 1 AND 9999', name: 'coaching_previous_year'
    add_check_constraint :coaching_changes, "status IN ('pending', 'confirmed', 'rejected')", name: 'coaching_status'

    create_table :coaching_reviews do |t|
      t.integer :year, null: false
      t.boolean :ready, null: false, default: false
      t.timestamps
    end
    add_index :coaching_reviews, :year, unique: true
    add_check_constraint :coaching_reviews, 'year BETWEEN 1 AND 9999', name: 'coaching_review_year'
  end
end
