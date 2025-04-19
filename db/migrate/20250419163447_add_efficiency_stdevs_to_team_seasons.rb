class AddEfficiencyStdevsToTeamSeasons < ActiveRecord::Migration[7.1]
  def change
    add_column :team_seasons, :offensive_efficiency_std_dev, :decimal, precision: 6, scale: 3
    add_column :team_seasons, :defensive_efficiency_std_dev, :decimal, precision: 6, scale: 3
  end
end
