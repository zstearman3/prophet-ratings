class CreateTeamSeasons < ActiveRecord::Migration[7.0]
  def change
    create_table :team_seasons do |t|
      t.references :team, null: false
      t.references :season, null: false
      t.timestamps
    end
  end
end
