# frozen_string_literal: true

class AddSportsReferenceSlugsToConferences < ActiveRecord::Migration[8.1]
  def change
    add_column :conferences, :sports_reference_slugs, :string, array: true, default: [], null: false
  end
end
