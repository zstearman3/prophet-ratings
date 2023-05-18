class CreateGames < ActiveRecord::Migration[7.0]
  def change
    create_table :games do |t|
      t.references :home_team, index: true, null: true, foreign_key: {to_table: :teams}
      t.references :away_team, index: true, null: true, foreign_key: {to_table: :teams}
      t.string :url, null: false
      t.datetime :start_time, null: false
      t.timestamps
    end
  end
end
