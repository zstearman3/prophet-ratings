class AddWinsAndLossesToTeamSeasons < ActiveRecord::Migration[7.1]
  def change
    add_column :team_seasons, :wins, :integer, default: 0
    add_column :team_seasons, :losses, :integer, default: 0
  end
end
