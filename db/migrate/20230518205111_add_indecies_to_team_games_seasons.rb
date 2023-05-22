class AddIndeciesToTeamGamesSeasons < ActiveRecord::Migration[7.0]
  def change
    add_reference :games, :season, null: false
    add_column :team_games, :home, :boolean
    remove_reference :games, :home_team
    remove_reference :games, :away_team
    add_index :team_seasons, [:team_id, :season_id], unique: true
    add_index :team_games, [:team_id, :game_id], unique: true
    add_index :team_games, [:game_id, :home], unique: true
  end
end
