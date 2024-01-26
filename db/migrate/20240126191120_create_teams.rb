class CreateTeams < ActiveRecord::Migration[7.1]
  def change
    create_table :teams do |t|
      t.string "school"
      t.string "nickname"
      t.string "url"
      t.string "location"
      t.index ["school"], name: "index_teams_on_school", unique: true
      
      t.timestamps
    end
  end
end
