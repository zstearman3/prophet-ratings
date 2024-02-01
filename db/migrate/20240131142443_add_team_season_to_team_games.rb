class AddTeamSeasonToTeamGames < ActiveRecord::Migration[7.1]
  def change
    add_reference :team_games, :team_season, index: true
  end
end
