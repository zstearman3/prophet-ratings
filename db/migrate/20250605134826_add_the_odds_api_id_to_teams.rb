class AddTheOddsApiIdToTeams < ActiveRecord::Migration[7.1]
  def change
    add_column :teams, :the_odds_api_team_id, :string
    add_index :teams, :the_odds_api_team_id, unique: true
  end
end
