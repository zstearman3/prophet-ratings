class CreateTeamOffseasonProfiles < ActiveRecord::Migration[7.1]
  def change
    create_table :team_offseason_profiles do |t|
      t.belongs_to :team_season, null: false
      t.integer :recruiting_class_rank
      t.float   :recruiting_score
      t.float   :returning_minutes_pct
      t.float   :returning_bpm_total
      t.integer :lost_starters
      t.boolean :coaching_change
      t.float   :manual_adjustment
      t.timestamps
    end
  end
end
