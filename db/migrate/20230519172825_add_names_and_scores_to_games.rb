class AddNamesAndScoresToGames < ActiveRecord::Migration[7.0]
  def change
    add_column :games, :home_team_name, :string, null: false
    add_column :games, :away_team_name, :string, null: false
    add_column :games, :home_team_score, :integer
    add_column :games, :away_team_score, :integer
    add_column :games, :possessions, :decimal, precision: 4, scale: 1
    add_column :games, :neutral, :boolean
    add_column :games, :location, :string
  end
end
