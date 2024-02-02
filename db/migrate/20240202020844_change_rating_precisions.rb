class ChangeRatingPrecisions < ActiveRecord::Migration[7.1]
  def change
    change_column :team_games, :offensive_rating, :decimal, precision: 6, scale: 3
    change_column :team_games, :defensive_rating, :decimal, precision: 6, scale: 3
    change_column :team_seasons, :offensive_efficiency, :decimal, precision: 6, scale: 3
    change_column :team_seasons, :defensive_efficiency, :decimal, precision: 6, scale: 3
    change_column :team_seasons, :pace, :decimal, precision: 6, scale: 3
    change_column :team_seasons, :adj_offensive_efficiency, :decimal, precision: 6, scale: 3
    change_column :team_seasons, :adj_defensive_efficiency, :decimal, precision: 6, scale: 3
    change_column :team_seasons, :adj_pace, :decimal, precision: 6, scale: 3
    change_column :team_seasons, :rating, :decimal, precision: 6, scale: 3
  end
end
