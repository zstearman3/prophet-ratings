class AddMinutesToGames < ActiveRecord::Migration[7.1]
  def change
    add_column :games, :minutes, :integer
  end
end
