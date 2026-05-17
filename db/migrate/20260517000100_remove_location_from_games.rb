# frozen_string_literal: true

class RemoveLocationFromGames < ActiveRecord::Migration[7.1]
  def change
    remove_column :games, :location, :string
  end
end
