class CreateTeamSeasons < ActiveRecord::Migration[7.1]
  def change
    create_table :team_seasons do |t|
      t.bigint "team_id", null: false
      t.bigint "season_id", null: false
      t.index ["season_id"], name: "index_team_seasons_on_season_id"
      t.index ["team_id", "season_id"], name: "index_team_seasons_on_team_id_and_season_id", unique: true
      t.index ["team_id"], name: "index_team_seasons_on_team_id"
      
      t.timestamps
    end
  end
end
