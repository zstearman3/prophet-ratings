class AddOpponentTeamSeasonToTeamGames < ActiveRecord::Migration[7.1]
  def change
    add_reference :team_games, :opponent_team_season, index: true, foreign_key: { to_table: :team_seasons }, null: true
  end
end
