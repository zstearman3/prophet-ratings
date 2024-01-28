class AddAveragesToTeamSeasons < ActiveRecord::Migration[7.1]
  def change
    add_column :team_seasons, :offensive_efficiency, :decimal, precision: 6, scale: 5
    add_column :team_seasons, :defensive_efficiency, :decimal, precision: 6, scale: 5
    add_column :team_seasons, :pace, :decimal, precision: 6, scale: 5
    add_column :team_seasons, :adj_offensive_efficiency, :decimal, precision: 6, scale: 5
    add_column :team_seasons, :adj_defensive_efficiency, :decimal, precision: 6, scale: 5
    add_column :team_seasons, :adj_pace, :decimal, precision: 6, scale: 5
    add_column :team_seasons, :rating, :decimal, precision: 6, scale: 5
  end
end
