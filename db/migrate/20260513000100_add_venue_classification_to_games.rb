# frozen_string_literal: true

class AddVenueClassificationToGames < ActiveRecord::Migration[7.1]
  def change
    add_column :games, :venue_type, :string, null: false, default: 'unknown'
    add_column :games, :venue_source, :string
    add_column :games, :venue_confidence, :string, null: false, default: 'unknown'
    add_column :games, :venue_name, :string

    add_index :games, :venue_type
    add_index :games, :venue_confidence
  end
end
