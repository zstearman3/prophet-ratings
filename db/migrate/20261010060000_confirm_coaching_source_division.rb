# frozen_string_literal: true

class ConfirmCoachingSourceDivision < ActiveRecord::Migration[8.1]
  def change
    add_column :coaching_changes, :previous_season_d1, :boolean, null: false, default: false
    # A new eligibility fact requires a deliberate review, including already-ready years.
    reversible do |direction|
      direction.up { execute 'UPDATE coaching_reviews SET ready = FALSE' }
    end
  end
end
