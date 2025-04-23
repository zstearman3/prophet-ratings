class AddPreseasonRatingToTeamSeasons < ActiveRecord::Migration[7.1]
  def change
    add_column :team_seasons, :preseason_adj_offensive_efficiency, :decimal, precision: 6, scale: 3
    add_column :team_seasons, :preseason_adj_defensive_efficiency, :decimal, precision: 6, scale: 3
    add_column :team_seasons, :preseason_adj_pace, :decimal, precision: 6, scale: 3
  end
end
