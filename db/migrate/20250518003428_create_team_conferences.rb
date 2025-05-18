class CreateTeamConferences < ActiveRecord::Migration[7.1]
  def change
    create_table :team_conferences do |t|

      t.references :team, null: false, foreign_key: true
      t.references :conference, null: false, foreign_key: true
      t.references :start_season, null: false, foreign_key: { to_table: :seasons }
      t.references :end_season, null: true, foreign_key: { to_table: :seasons }

      t.timestamps
    end

    add_index :team_conferences, [:team_id, :start_season_id, :end_season_id], unique: true, name: "index_team_conferences_on_team_and_season_range"
  end
end
