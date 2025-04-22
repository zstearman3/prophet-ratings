class CreateTeamRatingSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :team_rating_snapshots do |t|
      t.references :team, null: false, foreign_key: true
      t.references :season, null: false, foreign_key: true
      t.references :team_season, null: false, foreign_key: true
      t.date :snapshot_date, null: false
      t.string :config_bundle_name

      t.decimal :rating, precision: 6, scale: 3
      t.decimal :adj_offensive_efficiency, precision: 6, scale: 3
      t.decimal :adj_defensive_efficiency, precision: 6, scale: 3
      t.decimal :adj_pace, precision: 6, scale: 3

      t.jsonb :stats, default: {}, null: false

      t.timestamps
    end

    add_index :team_rating_snapshots, [:team_id, :season_id, :snapshot_date]
    add_index :team_rating_snapshots, [:rating, :snapshot_date]
    add_index :team_rating_snapshots, [:team_id, :snapshot_date, :config_bundle_name], unique: true
  end
end