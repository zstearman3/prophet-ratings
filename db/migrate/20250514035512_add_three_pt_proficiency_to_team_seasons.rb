class AddThreePtProficiencyToTeamSeasons < ActiveRecord::Migration[7.1]
  def change
    add_column :team_seasons, :three_pt_proficiency, :decimal, precision: 6, scale: 5
  end
end
