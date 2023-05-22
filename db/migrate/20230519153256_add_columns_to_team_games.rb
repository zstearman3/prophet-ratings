class AddColumnsToTeamGames < ActiveRecord::Migration[7.0]
  def change
    add_column :games, :status, :integer, null: false, default: 0
    add_column :team_games, :minutes, :integer
    add_column :team_games, :field_goals_made, :integer
    add_column :team_games, :field_goals_attempted, :integer
    add_column :team_games, :field_goals_percentage, :decimal, precision: 6, scale: 5
    add_column :team_games, :two_pt_made, :integer
    add_column :team_games, :two_pt_attempted, :integer
    add_column :team_games, :two_pt_percentage, :decimal, precision: 6, scale: 5
    add_column :team_games, :three_pt_made, :integer
    add_column :team_games, :three_pt_attempted, :integer
    add_column :team_games, :three_pt_percentage, :decimal, precision: 6, scale: 5
    add_column :team_games, :free_throws_made, :integer
    add_column :team_games, :free_throws_attempted, :integer
    add_column :team_games, :free_throws_percentage, :decimal, precision: 6, scale: 5
    add_column :team_games, :offensive_rebounds, :integer
    add_column :team_games, :defensive_rebounds, :integer
    add_column :team_games, :rebounds, :integer
    add_column :team_games, :assists, :integer
    add_column :team_games, :steals, :integer
    add_column :team_games, :blocks, :integer
    add_column :team_games, :turnovers, :integer
    add_column :team_games, :fouls, :integer
    add_column :team_games, :points, :integer
    add_column :team_games, :true_shooting_percentage, :decimal, precision: 6, scale: 5
    add_column :team_games, :effective_fg_percentage, :decimal, precision: 6, scale: 5
    add_column :team_games, :three_pt_attempt_rate, :decimal, precision: 6, scale: 5
    add_column :team_games, :free_throw_rate, :decimal, precision: 6, scale: 5
    add_column :team_games, :offensive_rebound_rate, :decimal, precision: 6, scale: 5
    add_column :team_games, :defensive_rebound_rate, :decimal, precision: 6, scale: 5
    add_column :team_games, :rebound_rate, :decimal, precision: 6, scale: 5
    add_column :team_games, :assist_rate, :decimal, precision: 6, scale: 5
    add_column :team_games, :steal_rate, :decimal, precision: 6, scale: 5
    add_column :team_games, :block_rate, :decimal, precision: 6, scale: 5
    add_column :team_games, :turnover_rate, :decimal, precision: 6, scale: 5
    add_column :team_games, :offensive_rating, :decimal, precision: 6, scale: 5
    add_column :team_games, :defensive_rating, :decimal, precision: 6, scale: 5
  end
end
